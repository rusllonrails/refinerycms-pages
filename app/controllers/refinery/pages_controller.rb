module Refinery
  class PagesController < ::ApplicationController
    include Pages::RenderOptions

    before_action :find_page, :set_canonical
    before_action :error_404, unless: :current_user_can_view_page?
    before_action :check_page_permissions!, only: [:show]
    before_action :add_default_breadcrumbs
    before_action :add_breadcrumbs, :only => [:show]
    before_action :find_all_categories
    before_action :find_featured_suppliers, :only => [:home]
    before_action :find_featured_member, only: [:home]

    # Save whole Page after delivery
    after_action :write_cache?

    # This action is usually accessed with the root path, normally '/'
    def home
      if is_marketplace?
        check_if_user_need_to_change_password!

        @posts = Refinery::Blog::Post.live.limit(5)
        @page = Refinery::Page.first
        @categories = Refinery::Marketplaces::Category.all
        @categories_layout_class = categories_layout_class(@categories.count)

        render template: "/refinery/marketplaces/pages/home"
      else
        render_with_templates?
      end
    end

    def categories_layout_class(categories_count)
      # five columns by default
      categories_layout = 5
      if @categories.count > 5
        if categories_count == 6
          # three columns
          categories_layout = 3
        elsif categories_count % 4 == 0 || (categories_count % 4 > 2 && categories_count % 5 != 0)
          # four columns
          categories_layout = 4
        end
      else
        categories_layout = "justify"
      end

      return "category-layout-#{categories_layout}"
    end

    # This action can be accessed normally, or as nested pages.
    # Assuming a page named "mission" that is a child of "about",
    # you can access the pages with the following URLs:
    #
    #   GET /pages/about
    #   GET /about
    #
    #   GET /pages/mission
    #   GET /about/mission
    #
    def show
      if should_skip_to_first_child?
        redirect_to refinery.url_for(first_live_child.url) and return
      elsif page.link_url.present?
        redirect_to page.link_url and return
      elsif should_redirect_to_friendly_url?
        redirect_to refinery.url_for(page.url), :status => 301 and return
      end

      render_with_templates?
    end

    def layout_by_subdomain
      if is_marketplace?
        "marketplace"
      else
        "application"
      end
    end

  protected

    def requested_friendly_id
      if ::Refinery::Pages.scope_slug_by_parent
        # Pick out last path component, or id if present
        "#{params[:path]}/#{params[:id]}".split('/').last
      else
        # Remove leading and trailing slashes in path, but leave internal
        # ones for global slug scoping
        params[:path].to_s.gsub(%r{\A/+}, '').presence || params[:id]
      end
    end

    def should_skip_to_first_child?
      page.skip_to_first_child && first_live_child
    end

    def should_redirect_to_friendly_url?
      requested_friendly_id != page.friendly_id || (
        ::Refinery::Pages.scope_slug_by_parent &&
        params[:path].present? && params[:path].match(page.root.slug).nil?
      )
    end

    def current_user_can_view_page?
      page.live? || current_refinery_user_can_access?("refinery_pages")
    end

    def current_refinery_user_can_access?(plugin)
      admin? && authorisation_manager.allow?(:plugin, plugin)
    end

    def first_live_child
      page.children.order('lft ASC').live.first
    end

    def find_page(fallback_to_404 = true)
      @page ||= action_page_finder.call(params) if action_has_page_finder?
      @page || (error_404 if fallback_to_404)
    end

    alias_method :page, :find_page


    def find_featured_member
      @featured_member = Refinery::Websites::User.with_role('Featured Member').order('RAND()').first
    end

    ## START OF MARKETPLACE ##
    def find_all_categories
      @categories = Refinery::Marketplaces::Category.all
    end

    def find_featured_suppliers
      @featured_suppliers = Refinery::Marketplaces::Business.suppliers.with_logo.includes(:category).order("created_at DESC").limit(3)
    end

    ## END OF MARKETPLACE ##

    def check_page_permissions!
      if @page.members_only?
        session[:redirect_to_uri] = request.fullpath

        if current_website_user.present?
          if !@page.allowed_user?(current_website_user)
            redirect_to "/members-only"
            return
          end
        else
          redirect_to "/members-only"
          return
        end
      end
    end

    def add_default_breadcrumbs
      add_crumb "Home", '/'
    end

    def add_breadcrumbs
      pages = get_parent_pages(@page)
      add_crumbs_for_pages(pages)
    end

    def add_crumbs_for_pages(pages)
      pages.each do |page|
        if page.menu_title.present?
          add_crumb page.menu_title, view_context.refinery.page_path(page)
        else
          add_crumb page.title, view_context.refinery.page_path(page)
        end
      end
    end

    # Should be on the model
    def get_parent_pages(page)
      parent_pages = [page]
      while page.parent
        parent_pages << page.parent
        page = page.parent
      end
      parent_pages.reverse
    end

    def set_canonical
      @canonical = refinery.url_for @page.canonical if @page.present?
    end

    def write_cache?
      # Don't cache the page with the site bar showing.
      if Refinery::Pages.cache_pages_full && !authorisation_manager.allow?(:read, :site_bar)
        cache_page(response.body, File.join('', 'refinery', 'cache', 'pages', request.path).to_s)
      end
    end

    private
    def action_has_page_finder?
      Finders.const_defined? action_name.classify
    end

    def action_page_finder
      Finders.const_get action_name.classify
    end

    module Finders
      class Home
        def self.call(_params)
          Refinery::Page.find_by link_url: "/"
        end
      end

      class Show
        def self.call(params)
          Refinery::Page.friendly.find_by_path_or_id params[:path], params[:id]
        end
      end
    end
  end
end
