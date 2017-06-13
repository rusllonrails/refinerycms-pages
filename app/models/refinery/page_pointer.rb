#
# THIS MODEL IS a SPEED PERFORMANCE SOLUTION
# for /refinery/pages section
# It is like a lightweight pointer
#

module Refinery
  class PagePointer < ActiveRecord::Base

    self.table_name = "page_pointers"

    belongs_to :page, foreign_key: :page_id,
                      class_name: "Refinery::Page"

    scope :roots, -> {
      where(parent_id: nil)
    }

    validates :page_id, :title, presence: true

    def children
      self.class.where(parent_id: page_id).order('lft ASC')
    end

    def id
      page_id
    end

    def nested_url
      JSON.parse(super())
    end

    def url
      Pages::Url.build(self)
    end
  end
end
