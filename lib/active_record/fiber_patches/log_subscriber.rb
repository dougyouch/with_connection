module ActiveRecord
  module ConnectionAdapters
    class FiberedMonitor
      class LogSubscriber < ActiveSupport::LogSubscriber
        def wait(event)
          return unless logger && logger.debug?
          logger.debug "waited " + (" (%.1fms)" % event.duration) + " for a #{event.payload[:resource]}"
        end
      end
    end
  end
end
ActiveRecord::ConnectionAdapters::FiberedMonitor::LogSubscriber.attach_to :connection_pool
