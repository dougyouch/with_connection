# Necessary monkeypatching to make AR fiber-friendly.

module ActiveRecord
  module ConnectionAdapters

    def self.fiber_pools
      @fiber_pools ||= []
    end
    def self.register_fiber_pool(fp)
      fiber_pools << fp
    end

    class FiberedMonitor
      class Queue
        def initialize
          @queue = []
        end

        def wait(timeout)
          t = timeout || 5
          fiber = Fiber.current
          x = EM::Timer.new(t) do
            @queue.delete(fiber)
            fiber.resume(false)
          end
          @queue << fiber
          Fiber.yield.tap do
            x.cancel
          end
        end

        def signal
          fiber = @queue.pop
          fiber.resume(true) if fiber
        end
      end

      def synchronize
        yield
      end

      def new_cond
        Queue.new
      end
    end

    # ActiveRecord's connection pool is based on threads.  Since we are working
    # with EM and a single thread, multiple fiber design, we need to provide
    # our own connection pool that keys off of Fiber.current so that different
    # fibers running in the same thread don't try to use the same connection.
    class ConnectionPool
      def initialize(spec)
        @spec = spec

        # The cache of reserved connections mapped to threads
        @reserved_connections = {}

        # The mutex used to synchronize pool access
        @connection_mutex = FiberedMonitor.new
        @queue = @connection_mutex.new_cond

        # default 5 second timeout unless on ruby 1.9
        @timeout = spec.config[:wait_timeout] || 5

        # default max pool size to 5
        @size = (spec.config[:pool] && spec.config[:pool].to_i) || 5

        @connections = []
        @checked_out = []
        @automatic_reconnect = true
        @tables = {}

        @columns     = Hash.new do |h, table_name|
          h[table_name] = with_connection do |conn|

            # Fetch a list of columns
            conn.columns(table_name, "#{table_name} Columns").tap do |columns|

              # set primary key information
              columns.each do |column|
                column.primary = column.name == primary_keys[table_name]
              end
            end
          end
        end

        @columns_hash = Hash.new do |h, table_name|
          h[table_name] = Hash[columns[table_name].map { |col|
            [col.name, col]
          }]
        end

        @primary_keys = Hash.new do |h, table_name|
          h[table_name] = with_connection do |conn|
            table_exists?(table_name) ? conn.primary_key(table_name) : 'id'
          end
        end
      end

      def clear_stale_cached_connections!
        cache = @reserved_connections
        keys = Set.new(cache.keys)

        ActiveRecord::ConnectionAdapters.fiber_pools.each do |pool|
          pool.busy_fibers.each_pair do |object_id, fiber|
            keys.delete(object_id)
          end
        end

        keys.each do |key|
          next unless cache.has_key?(key)
          checkin cache[key]
          cache.delete(key)
        end
      end

      def valid_busy_fiber?
        ActiveRecord::ConnectionAdapters.fiber_pools.any? do |pool|
          pool.busy_fibers[current_connection_id]
        end
      end

      def connection_with_sanity_check
        raise "not a busy fiber" if EM.reactor_running? && ! valid_busy_fiber?
        connection_without_sanity_check
      end

      unless Rails.env == 'production'
        alias_method_chain :connection, :sanity_check
      end

      private

      def current_connection_id #:nodoc:
        Fiber.current.object_id
      end

      def checkout_and_verify(c)
        @checked_out << c
        begin
          c.run_callbacks :checkout
          c.verify!
        rescue Exception => e
          @checked_out.delete c
          raise e
        end
        c
      end
    end

  end
end
