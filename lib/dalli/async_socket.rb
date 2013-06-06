module Dalli
  class Server
    class KAsyncSocket < EventMachine::Synchrony::TCPSocket
      def readfull(count)
        value = ''
        read count, value
        value
      end
    end

    class KSocket
      class << self
        def open_with_async(*args)
          if EM.reactor_running?
            KAsyncSocket.new *args
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
