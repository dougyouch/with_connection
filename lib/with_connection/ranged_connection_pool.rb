module WithConnection
  class RangedConnectionPool
    attr_reader :list, :default_pool, :key_algo

    def initialize(ranges_and_pools, default_pool, key_algo)
      @list = ranges_and_pools.map { |range, pool| Item.new(range, pool) }
      @default_pool = default_pool
      @key_algo = key_algo
    end

    def with_connection(key=nil, read_write=nil, &block)
      local_current[:with_connection_ranged_connection_pool] = pool_for_key(key, read_write)
      local_current[:with_connection_ranged_connection_pool].with_connection(key, read_write, &block)
    ensure
      local_current[:with_connection_ranged_connection_pool] = nil
    end

    def connection
      local_current[:with_connection_ranged_connection_pool].try(:connection) || @default_pool.connection
    end

    def pool_for_key(key, read_write)
      key = self.key_algo.call(key) if key
      key.nil? ?
      @default_pool : 
        (@list.detect { |item| item.include?(key) }.try(:pool) || @default_pool)
    end

    def local_current
      defined?(EM) && EM.reactor_running? ? Fiber.current : Thread.current
    end

    def create_all_connections
      @default_pool.create_all_connections
      @list.each { |item| item.pool.create_all_connections }
    end

    def disconnect!
      @default_pool.disconnect!
      @list.each { |item| item.pool.disconnect! }
    end

    class Item
      attr_reader :range, :pool

      def initialize(range, pool)
        @range = range
        @pool = pool
      end

      def include?(key)
        @range.include? key
      end
    end

    class BasicRange
      attr_reader :lo, :hi

      def initialize(lo, hi)
        @lo = lo
        @hi = hi
      end

      def include?(val)
        val >= lo && val <= hi
      end
    end
  end
end
