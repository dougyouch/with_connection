module ActiveSupport
  module Cache
    class MemcacheConnectionPool
      attr_reader :options

      def initialize(options)
        @options = options
      end

      def fetch(name, options=nil)
        with_connection do
          options ? connection.fetch(name, options) : connection.fetch(name)
        end
      end

      def read(name, options=nil)
        with_connection do
          options ? connection.read(name, options) : connection.read(name)
        end
      end

      def write(name, value, options=nil)
        with_connection do
          options ? connection.write(name, value, options) : connection.write(name, value)
        end
      end

      def exist?(name, options=nil)
        with_connection do
          options ? connection.exist?(name, options) : connection.exist?(name)
        end
      end

      def delete(name, options=nil)
        with_connection do
          options ? connection.delete(name, options) : connection.delete(name)
        end
      end

      def read_multi(*names)
        with_connection do
          connection.read_multi *names
        end
      end

      def increment(name, amount = 1, options=nil)
        with_connection do
          options ? connection.increment(name, amount, options) : connection.increment(name, amount)
        end
      end

      def decrement(name, amount = 1, options=nil)
        with_connection do
          options ? connection.decrement(name, amount, options) : connection.decrement(name, amount)
        end
      end

      def reset(options=nil)
        with_connection do
          options ? connection.reset(options) : connection.reset
        end
      end
      alias clear reset

      if defined?(EM)
        def sync_connection_pool
          @sync_connection_pool ||=
            begin
              spec = ActiveRecord::Base::ConnectionSpecification.new @options.dup, @options[:adapter_method]
              WithConnection::ConnectionPool.new @options[:name], spec
            end
        end

        def async_connection_pool
          @async_connection_pool ||=
            begin
              spec = ActiveRecord::Base::ConnectionSpecification.new @options.merge(:async => true), (@options[:async_adapter_method] || @options[:adapter_method])
              WithConnection::ConnectionPool.new @options[:name], spec
            end
        end

        def connection_pool
          EM.reactor_running? ? async_connection_pool : sync_connection_pool
        end
      else
        def connection_pool
          @connection_pool ||=
            begin
              spec = ActiveRecord::Base::ConnectionSpecification.new @options.dup, @options[:adapter_method]
              WithConnection::ConnectionPool.new @options[:name], spec
            end
        end
      end

      def with_connection(&block)
        connection_pool.with_connection(&block)
      end

      def connection
        connection_pool.connection
      end
    end
  end
end
