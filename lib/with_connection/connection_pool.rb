require "active_record/connection_adapters/abstract/connection_pool"

module WithConnection
  class ConnectionPool < ActiveRecord::ConnectionAdapters::ConnectionPool
    attr_reader :name

    def initialize(name, spec)
      @name = name
      super spec
      @disable_warning = !! spec.config[:disable_warning]
      @debug_with_connection = !! spec.config[:debug_with_connection]
      ConnectionManagement.connection_pools << self
    end

    def has_connection?
      !! @reserved_connections[current_connection_id]
    end

    def with_connection(key=nil, read_write=nil)
      connection_id = current_connection_id
      fresh_connection = true unless @reserved_connections[connection_id]
      yield connection
    ensure
      release_connection(connection_id) if fresh_connection
    end

    def with_connection_with_debug(key=nil, read_write=nil, &block)
      @using_with_connection = true
      with_connection_without_debug(key, read_write, &block).tap { @using_with_connection = false }
    end
    alias_method_chain :with_connection, :debug

    def checkout_with_debug
      if @debug_with_connection && ! @using_with_connection
        Rails.logger.warn "#{name} not using with_connection, backtrace: #{caller.inspect}"
      end

      begin
        checkout_without_debug
      rescue ActiveRecord::ConnectionTimeoutError => e
        raise ActiveRecord::ConnectionTimeoutError, "could not obtain a #{name} connection#{" within #{@timeout} seconds" if @timeout}.  The max pool size is currently #{@size}; consider increasing it."
      end
    end
    alias_method_chain :checkout, :debug

    def release_connection_with_warning
      Rails.logger.warn "#{@name} connection was held by the request" if ! @disable_warning && has_connection?
      release_connection
    end

    def create_all_connections
      @size.times { @connections << new_connection }
    end

    private
    def new_connection
      spec.adapter_method.call spec.config
    end
  end

  class ConnectionManagement
    @@connection_pools = []
    def self.connection_pools
      @@connection_pools
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    ensure
      # Don't return connection (and perform implicit rollback) if
      # this request is a part of integration test
      unless env.key?("rack.test")
        self.class.connection_pools.each(&:release_connection_with_warning)
      end
    end
  end
end
