module WithConnection
  class RangedConnectionPool
    attr_reader :list, :default_pool, :key_algo

    def initialize(ranges_and_pools, default_pool, key_algo)
      @list = ranges_and_pools.map { |range, pool| Item.new(range, pool) }
      @default_pool = default_pool
      @key_algo = key_algo
    end

    def with_connection(key=nil, &block)
      local_current[:pool] = pool_for_key(key)
      local_current[:pool].with_connection(&block)
    end

    def connection
      local_current[:pool] ||= @default_pool
      local_current[:pool].connection
    end

    def pool_for_key(key)
      key = self.key_algo.call(key) if key
      key.nil? ?
      @default_pool : 
        (@list.detect { |item| item.include?(key) } || @default_pool)
    end

    def local_current
      defined?(EM) && EM.reactor_running? ? Fiber.current : Thread.current
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
