module ActiveRecord
  module ConnectionAdapters
    class ConnectionPool
      module RoundRobin
        # when checking in a connection put it at the end of the connections array.
        # this way all the connections get used
        def checkin(conn)
          @connection_mutex.synchronize do
            conn.send(:_run_checkin_callbacks) do
              @connections.delete conn
              @connections.push conn
              @checked_out.delete conn
              @queue.signal
            end
          end
        end
      end
    end
  end
end
