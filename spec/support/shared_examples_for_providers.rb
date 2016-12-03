require 'spec_helper'
require 'colored2'
require 'simplefeed/dsl'

def ensure_descending(r)
  last_event = nil
  r.each do |event|
    if last_event
      expect(event.time).to be <= last_event.time
    end
    last_event = event
  end
end

# Requires the following variables set:
#  * provider_opts

shared_examples 'a provider' do
  subject(:feed) {
    SimpleFeed.define(:tested_feed) do |f|
      f.max_size = 5
      f.provider = described_class.new(provider_opts)
    end
  }

  let(:provider) { feed.provider.provider }
  before { feed }

  include_context :event_matrix

  let(:user_id) { 99119911 }
  let(:activity) { feed.activity(user_id) }

  # Reset the feed with a wipe, and ensure the size is zero
  before { with_activity(activity) { wipe; total_count { |r| expect(r).to eq(0) } } }

  context '#store' do
    context 'new events' do
      it 'returns valid responses back from each operation' do
        with_activity(activity, events: events) do
          store(events.first) { |r| expect(r).to eq(true) }
          total_count { |r| expect(r).to eq(1) }

          store(events.last) { |r| expect(r).to eq(true) }
          total_count { |r| expect(r).to eq(2) }
        end
      end
    end

    context 'storing new events' do
      it 'returns valid responses back from each operation' do
        with_activity(activity, events: events) do
          store(events.first) { |r| expect(r).to eq(true) }
          store(events.first) { |r| expect(r).to eq(false) }

          store(events.last) { |r| expect(r).to eq(true) }
          store(events.last) { |r| expect(r).to eq(false) }
        end
      end
    end

    context 'storing and removing events' do
      before do
        with_activity(activity, events: events) do
          store(events.first) { |r| expect(r).to eq(true) }
          store(events.last) { |r| expect(r).to eq(true) }
          total_count { |r| expect(r).to eq(2) }
        end
      end

      context '#delete' do
        it('with event as an argument') do
          with_activity(activity, events: events) do
            delete(events.first) { |r| expect(r).to eq(true) }
            total_count { |r| expect(r).to eq(1) }
          end
        end
        it('with event value as an argument') do
          with_activity(activity, events: events) do
            delete(events.first.value) { |r| expect(r).to eq(true) }
            total_count { |r| expect(r).to eq(1) }
          end
        end
      end

      context '#delete_if' do
        let(:activity) { feed.activity(user_id) }
        it 'should delete events that match' do
          expect(activity.total_count).to eq(2)
          activity.delete_if do |user_id, evt|
            evt == events.first
          end
          expect(activity.total_count).to eq(1)
          expect(activity.fetch).to include(events.last)
          expect(activity.fetch).not_to include(events.first)
        end
      end

      context 'hitting #max_size of the feed' do
        it('pushes the oldest one out') do
          with_activity(activity, events: events) do
            wipe
            reset_last_read
            store(value: 'new story') { |r| expect(r).to be(true) }
            store(value: 'old one', at: Time.now - 7200) { |r| expect(r).to be(true) }
            store(value: 'older one', at: Time.now - 8000) { |r| expect(r).to be(true) }
            store(value: 'and one more') { |r| expect(r).to be(true) }
            store(value: 'the oldest', at: Time.now - 20000) { |r| expect(r).to be(true) }
            store(value: 'and two more', at: Time.now + 10) { |r| expect(r).to be(true) }

            fetch do |r|
              ensure_descending(r)
              expect(r.size).to eq(5)
            end
            fetch { |r| expect(r.map(&:value)).not_to include('the oldest') }
          end
        end
      end

      context '#paginate' do
        let(:ts) { Time.now }
        it 'resets last read, and returns the first event as page 1' do
          with_activity(activity, events: events) do
            unread_count { |r| expect(r).to eq(2) }
            reset_last_read { |r| expect(r.to_f).to be_within(0.01).of(Time.now.to_f) }
            unread_count { |r| expect(r).to eq(0) }
            store(value: 'new story') { |r| expect(r).to be(true) }
            unread_count { |r| expect(r).to eq(1) }
          end
        end
      end

      context '#fetch' do
        it 'fetches all elements sorted by time desc' do
          with_activity(activity, events: events) do
            reset_last_read
            store(value: 'new story') { |r| expect(r).to be(true) }
            store(value: 'and another', at: Time.now - 7200) { |r| expect(r).to be(true) }
            store(value: 'and one more') { |r| expect(r).to be(true) }
            store(value: 'and two more') { |r| expect(r).to be(true) }

            fetch { |r| ensure_descending(r) }
          end
        end
      end
    end

    context '#namespace' do
      let(:feed_proc) { ->(namespace) {
        SimpleFeed.define("#{namespace}") do |f|
          f.max_size  = 5
          f.namespace = namespace
          f.provider  = described_class.new(provider_opts)
        end
      } }

      let(:feed_ns1) { feed_proc.call(:ns1) }
      let(:feed_ns2) { feed_proc.call(:ns2) }

      let(:ua_ns1) { feed_ns1.activity(user_id) }
      let(:ua_ns2) { feed_ns2.activity(user_id) }

      before do
        ua_ns1.wipe
        ua_ns1.store(value: 'ns1')

        ua_ns2.wipe
        ua_ns2.store(value: 'ns2')
      end

      it 'properly sets namespace on each feed' do
        expect(feed_ns1.namespace).to eq(:ns1)
        expect(feed_ns2.namespace).to eq(:ns2)
      end

      it 'does not conflict if namespaces are distinct' do
        expect(ua_ns1.fetch.map(&:value)).to eq(%w(ns1))
        expect(ua_ns2.fetch.map(&:value)).to eq(%w(ns2))
      end
    end

    context 'additional methods' do
      it '#total_memory_bytes' do
        expect(provider.total_memory_bytes).to be >  0
      end
      it '#total_users' do
        expect(provider.total_users).to eq(1)
      end
    end

  end
end
