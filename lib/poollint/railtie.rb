# frozen_string_literal: true

require "rails/railtie"

module PoolLint
  class Railtie < Rails::Railtie
    initializer "poollint.install" do
      PoolLint.install!
    end
  end
end
