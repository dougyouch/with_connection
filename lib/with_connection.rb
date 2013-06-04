require 'rails/all'

module WithConnection
  extend ActiveSupport::Autoload

  autoload :ConnectionPool
end
