require 'base62-rb'
require 'hashie'
require 'set'
require 'knjrbfw'

require 'simplefeed/event'
require_relative 'paginator'
require_relative '../serialization/key'
require_relative '../base/provider'

module SimpleFeed
  module Providers
    module Hash
      class Provider < ::SimpleFeed::Providers::Base::Provider
        attr_accessor :h

        include SimpleFeed::Providers::Hash::Paginator

        def self.from_yaml(file)
          self.new(YAML.load(File.read(file)))
        end

        def initialize(**opts)
          self.h = {}
          h.merge!(opts)
        end

        def store(user_ids:, value:, at: Time.now)
          event = create_event(value, at)
          with_response_batched(user_ids) do |key|
            add_event(event, key)
          end
        end

        def delete(user_ids:, value:, at: nil)
          event = create_event(value, at)
          with_response_batched(user_ids) do |key|
            changed_activity_size?(key) do
              __delete(key, event)
            end
          end
        end

        def delete_if(user_ids:, &block)
          with_response_batched(user_ids) do |key|
            activity(key).each do |event|
              __delete(key, event) if yield(key.user_id, event)
            end
          end
        end

        def wipe(user_ids:)
          with_response_batched(user_ids) do |key|
            deleted = activity(key).size > 0
            wipe_user_record(key)
            deleted
          end
        end

        def fetch(user_ids:)
          with_response_batched(user_ids) do |key|
            activity(key)
          end
        end

        def paginate(user_ids:, page:, per_page: feed.per_page, **options)
          reset_last_read(user_ids: user_ids) unless options[:peek]
          with_response_batched(user_ids) do |key|
            activity = activity(key)
            (page && page > 0) ? activity[((page - 1) * per_page)...(page * per_page)] : activity
          end
        end

        def reset_last_read(user_ids:, at: Time.now)
          with_response_batched(user_ids) do |key|
            user_record(key)[:last_read] = at
            at
          end
        end

        def total_count(user_ids:)
          with_response_batched(user_ids) do |key|
            activity(key).size
          end
        end

        def unread_count(user_ids:)
          with_response_batched(user_ids) do |key|
            activity(key).count { |event| event.at > user_record(key).last_read.to_f }
          end
        end

        def last_read(user_ids:)
          with_response_batched(user_ids) do |key|
            user_record(key).last_read
          end
        end

        def total_memory_bytes
          analyzer = Knj::Memory_analyzer::Object_size_counter.new(self.h)
          analyzer.calculate_size
        end

        def total_users
          self.h.size
        end

        private

        #===================================================================
        # Methods below operate on a single user only
        #


        def changed_activity_size?(key)
          ua          = activity(key)
          size_before = ua.size
          yield(key, ua)
          size_after = activity(key).size
          (size_before > size_after)
        end

        def create_user_record
          Hashie::Mash.new(
            { last_read: 0, activity: SortedSet.new }
          )
        end

        def user_record(key)
          h[key.data] ||= create_user_record
        end

        def wipe_user_record(key)
          h[key.data] = create_user_record
        end

        def activity(key, event = nil)
          user_record(key)[:activity] << event if event
          user_record(key)[:activity].to_a
        end

        def add_event(event, key)
          uas = user_record(key)[:activity]
          if uas.include?(event)
            false
          else
            uas << event.dup
            if uas.size > feed.max_size
              uas.delete(uas.to_a.last)
            end
            true
          end
        end

        def __last_read(key, value = nil)
          user_record(key)[:last_read]
        end

        def __delete(key, event)
          user_record(key)[:activity].delete(event)
        end

        def create_event(*args, **opts)
          ::SimpleFeed::Event.new(*args, **opts)
        end
      end
    end
  end
end
