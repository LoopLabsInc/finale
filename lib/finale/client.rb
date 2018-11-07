require "rest-client"
require "json"
require "base64"
require "active_support/all"

require_relative"errors"
require_relative"order"
require_relative"shipment"

module Finale
  class Client
    MAX_REQUESTS = 100 # Finale API Usage: 'https://support.finaleinventory.com/hc/en-us/articles/115007830648-Getting-Started'
    BASE_URL     = 'https://app.finaleinventory.com'

    def initialize(account)
      @cookies       = nil
      @request_count = 0
      @account       = account
      @login_url     = construct_url(:auth)
      @order_url     = construct_url(:order)
      @shipment_url  = construct_url(:shipment)
    end

    def login(username: nil, password: nil)
      payload = {
        username: username || ENV['FINALE_USERNAME'],
        password: password || ENV['FINALE_PASSWORD']
      }

      request(verb: :LOGIN, payload: payload)
    end

    def get_shipment(id)
      response = request(verb: :GET, url: "#{@shipment_url}/#{id}")
      Shipment.new(response)
    end

    def get_order(id)
      response = request(verb: :GET, url: "#{@order_url}/#{id}")
      Order.new(response)
    end

    def get_orders(filter: nil)
      resp_orders = request(verb: :GET, url: @order_url, filter: filter )
      rows        = column_major_to_row_major(resp_orders)
      orders      = rows.map { |r| Order.new(r) }
      orders
    end

    def get_shipments(filter: nil)
      resp_shipments = request(verb: :GET, url: @shipment_url, filter: filter )
      rows           = column_major_to_row_major(resp_shipments)
      shipments      = rows.map { |r| Shipment.new(r) }
      shipments
    end

    def get_order_from_shipment(shipment)
      get_order(shipment.order_id)
    end

    def get_shipments_from_order(order)
      (order.shipmentUrlList || []).map do |suffix_url|
        url      = "#{BASE_URL}#{suffix_url}"
        response = request(verb: :GET, url: url)
        Shipment.new(response)
      end
    end

    private

    def column_major_to_row_major(column_major)
      row_major = []
      keys      = column_major.keys
      values    = column_major.values || [[]]
      num_cols  = values.count == 0 ? 0 : values.first.count
      num_cols.times do
        rowvals   = keys.map { |key| column_major[key].shift }
        row       = Hash[keys.zip(rowvals)]
        row_major << row
      end
      row_major
    end

    def construct_url(resource)
      "#{BASE_URL}/#{@account}/api/#{resource}"
    end

    def request(verb: nil, url: nil, payload: nil, filter: nil)
      raise MaxRequests.new(MAX_REQUESTS) if @request_count >= MAX_REQUESTS
      raise NotLoggedIn.new(verb: verb, url: url) unless verb == :LOGIN || !@cookies.nil?

      case verb
      when :LOGIN
        response = RestClient.post(@login_url, payload)
        @cookies = response.cookies
      when :GET
        params = {}

        if filter.present?
          encoded_filter = Base64.encode64(filter.to_json)
          params.merge!(filter: encoded_filter)
        end

        response = RestClient.get(url, cookies: @cookies, params: params)
      when :POST
        response = RestClient.post(url, cookies: @cookies)
      end

      @request_count += 1
      body = JSON.parse(response.body, symbolize_names: true)
      body
    end
  end
end

