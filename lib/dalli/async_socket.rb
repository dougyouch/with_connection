require 'timeout'

module Dalli
  class Server
    # from thrift_cliet-0.8.2/lib/thrift_client/event_machine.rb
    module EventMachineConnection
      GARBAGE_BUFFER_SIZE = 4096 # 4kB

      include EM::Deferrable

      def self.connect(host='localhost', port=11211, options={}, &block)
        fiber = Fiber.current
        EM.connect(host, port, self, host, port) do |conn|
          conn.pending_connect_timeout = options[:timeout] || 5
          conn.read_timeout = options[:read_timeout] || 5
          conn.write_timeout = options[:write_timeout] || 5
        end.tap do |connection|
          connection.callback do
            fiber.resume
          end

          connection.errback do
            fiber.resume
          end

          Fiber.yield

          raise Exception, "Unable to connect to #{host}:#{port}" unless connection.connected?
        end
      end

      def trap
        begin
          yield
        rescue Exception => ex
          puts ex.message
          puts ex.backtrace.join("\n")
        end
      end

      attr_accessor :read_timeout, :write_timeout

      def initialize(host, port=9090)
        @host, @port = host, port
        @index = 0
        @disconnected = 'not connected'
        @buf = ''
      end

      def close
        trap do
          @disconnected = 'closed'
          close_connection(true)
        end
      end

      def blocking_read(size)
        raise IOError, "lost connection to #{@host}:#{@port}: #{@disconnected}" if @disconnected
        if can_read?(size)
          yank(size)
        else
          raise ArgumentError, "Unexpected state" if @size or @callback

          timed(self.read_timeout) do
            read_with_callback size
          end
        end
      end
      alias readfull blocking_read

      # when enough data has been received the callback will return the data to the requesting fiber
      def read_with_callback(size)
        fiber = Fiber.current

        @size = size
        @callback = proc { |data|
          fiber.resume(data)
        }

        Fiber.yield
      end

      def write(buf)
        timed(self.write_timeout) do
          send_data buf
        end
      end

      def receive_data(data)
        trap do
          (@buf) << data

          if @callback and can_read?(@size)
            callback = @callback
            data = yank(@size)
            @callback = @size = nil
            callback.call(data)
          end
        end
      end

      def connected?
        !@disconnected
      end

      def connection_completed
        @disconnected = nil
        succeed
      end

      def unbind
        if !@disconnected
          @disconnected = 'unbound'
        else
          fail
        end
      end

      def can_read?(size)
        @buf.size >= @index + size
      end

      private

      def create_timer(timeout)
        fiber = Fiber.current

        EM::Timer.new(timeout) do
          self.close
          @size = nil
          @callback = nil
          @buf = ''
          @index = 0
          @timed_out = true
          fiber.resume false
        end
      end

      def timed(timeout)
        timer = create_timer(timeout)
        yield.tap do
          timer.cancel
          if @timed_out
            @timed_out = nil
            raise Timeout::Error, "connection to #{@host}:#{@port}: timed out while writing"
          end
        end
      end

      def yank(len)      
        data = @buf.slice(@index, len)
        @index += len
        @index = @buf.size if @index > @buf.size
        if @index >= GARBAGE_BUFFER_SIZE
          @buf = @buf.slice(@index..-1)
          @index = 0
        end
        data
      end
    end

    class KSocket
      class << self
        def open_with_async(*args)
          if EM.reactor_running?
            Dalli::Server::EventMachineConnection.connect *args
          else
            open_without_async *args
          end
        end
        alias open_without_async open
        alias open open_with_async
      end
    end
  end
end
