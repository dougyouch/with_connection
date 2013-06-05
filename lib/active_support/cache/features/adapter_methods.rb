module ActiveSupport
  module Cache
    module Features
      module AdapterMethods
        # method required by ActiveRecord::ConnectionAdapters::ConnectionPool
        def run_callbacks(method)
        end

        def verify!
        end

        def _run_checkin_callbacks
          yield if block_given?
        end

        def requires_reloading?
          true
        end

        def connected?
        end
      end
    end
  end
end
