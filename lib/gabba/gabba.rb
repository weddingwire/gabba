# yo, easy server-side tracking for Google Analytics... hey!
require "uri"
require "net/http"
require 'cgi'
require 'ga_cookie_parser'
require File.dirname(__FILE__) + '/version'

module Gabba

  class NoGoogleAnalyticsAccountError < RuntimeError; end
  class NoGoogleAnalyticsDomainError < RuntimeError; end
  class GoogleAnalyticsNetworkError < RuntimeError; end

  class Gabba
    GOOGLE_HOST = "www.google-analytics.com"
    BEACON_PATH = "/__utm.gif"
    USER_AGENT = "Gabba #{VERSION} Agent"

    # Custom var levels
    VISITOR = 1
    SESSION = 2
    PAGE    = 3

    ESCAPES = %w{ ' ! * ) }

    attr_accessor :utmwv, :utmn, :utmhn, :utmcs, :utmul, :utmdt, :utmp, :utmac, :utmt, :utmcc, :user_agent, :utma, :utmb, :utmz, :utmip

    # Public: Initialize Gabba Google Analytics Tracking Object.
    #
    # ga_acct - A String containing your Google Analytics account id.
    # domain  - A String containing which domain you want the tracking data to be logged from.
    # agent   - A String containing the user agent you want the tracking to appear to be coming from.
    #           Defaults to "Gabba 0.2 Agent" or whatever the corrent version is.
    #
    # Example:
    #
    #   g = Gabba::Gabba.new("UT-1234", "mydomain.com")
    #
    def initialize(ga_acct, domain, agent = Gabba::USER_AGENT, remote_ip = '')
      @utmwv = "4.4sh" # GA version
      @utmcs = "UTF-8" # charset
      @utmul = "en-us" # language

      @utmn = random_id
      @utmhid = random_id

      @utmac = ga_acct
      @utmhn = domain
      @user_agent = agent
      @utmip = utmip_fetch remote_ip
      @custom_vars = []
    end

    # Public: Set a custom variable to be passed along and logged by Google Analytics
    # (http://code.google.com/apis/analytics/docs/tracking/gaTrackingCustomVariables.html)
    #
    # index  - Integer between 1 and 5 for this custom variable
    # name   - String with the name of the custom variable
    # value  - String with the value for teh custom variable
    # scope  - Integer with custom variable scope must be 1 (VISITOR), 2 (SESSION) or 3 (PAGE)
    #
    # Example:
    #
    #   g = Gabba::Gabba.new("UT-1234", "mydomain.com")
    #   g.set_custom_var(1, 'awesomeness', 'supreme', Gabba::VISITOR)
    #   # => ['awesomeness', 'supreme', 1]
    #
    # Returns array with the custom variable data
    def set_custom_var(index, name, value, scope)
      raise "Index must be between 1 and 5" unless (1..5).include?(index)
      raise "Scope must be 1 (VISITOR), 2 (SESSION) or 3 (PAGE)" unless (1..3).include?(scope)

      @custom_vars[index] = [ name, value, scope ]
    end

    # Public: Delete a previously set custom variable so if is not passed along and logged by Google Analytics
    # (http://code.google.com/apis/analytics/docs/tracking/gaTrackingCustomVariables.html)
    #
    # index  - Integer between 1 and 5 for this custom variable
    #
    # Example:
    #   g = Gabba::Gabba.new("UT-1234", "mydomain.com")
    #   g.delete_custom_var(1)
    #
    def delete_custom_var(index)
      raise "Index must be between 1 and 5" unless (1..5).include?(index)

      @custom_vars.delete_at(index)
    end

    # Public: Renders the custom variable data in the format needed for GA
    # (http://code.google.com/apis/analytics/docs/tracking/gaTrackingCustomVariables.html)
    # Called before actually sending the data along to GA.
    def custom_var_data
      names  = []
      values = []
      scopes = []

      idx = 1
      @custom_vars.each_with_index do |(n, v, s), i|
        next if !n || !v || (/\w/ !~ n) || (/\w/ !~ v)
        prefix = "#{i}!" if idx != i
        names  << "#{prefix}#{escape(n)}"
        values << "#{prefix}#{escape(v)}"
        scopes << "#{prefix}#{escape(s)}"
        idx = i + 1
      end

      names.empty? ? "" : "8(#{names.join('*')})9(#{values.join('*')})11(#{scopes.join('*')})"
    end

    # Public: Record a page view in Google Analytics
    #
    # title   - String with the page title for thr page view
    # page    - String with the path for the page view
    # utmhid  - String with the unique visitor id, defaults to a new random value
    #
    # Example:
    #
    #   g = Gabba::Gabba.new("UT-1234", "mydomain.com")
    #   g.page_view("something", "track/me")
    #
    def page_view(title, page, utmhid = random_id)
      check_account_params
      cookies_parsed = GaCookieParser::GaCookieParser.new(:utmz => @utmz, :utma => @utma)
      today = Time.now
      if !@utma.blank? and @utmb.blank?
        @utma = "#{cookies_parsed.utma_hash[:domain_hash]}.#{cookies_parsed.utma_hash[:visitor_id]}.#{cookies_parsed.utma_hash[:initial_visit_at]}.#{cookies_parsed.utma_hash[:previous_visit_at]}.#{today.to_i}.#{cookies_parsed.utma_hash[:session_counter].to_i+1}"
      end

      unless @utmb.blank?
        temp = @utmb.split '.'
        temp[1] = temp[1].to_i + 1
        @utmb = temp.join '.'
      end

      unless @utmz.blank?
        @utmz = "#{cookies_parsed.utmz_hash[:domain_hash]}.#{cookies_parsed.utmz_hash[:timestamp]}.#{cookies_parsed.utmz_hash[:session_counter].to_i+1}.#{cookies_parsed.utmz_hash[:campaign_number]}.utmcsr=(#{cookies_parsed.utmz_hash[:utmcsr]})|utmccn=(#{cookies_parsed.utmz_hash[:utmccn]})|utmcmd=(#{cookies_parsed.utmz_hash[:utmcmd]})"
      end
      hey(page_view_params(title, page, utmhid))
    end

    # Public: Renders the page view params data in the format needed for GA
    # Called before actually sending the data along to GA.
    def page_view_params(title, page, utmhid = random_id)
      options = {
        :utmwv => @utmwv,
        :utmn => @utmn,
        :utmhn => @utmhn,
        :utmcs => @utmcs,
        :utmul => @utmul,
        :utmdt => title,
        :utmhid => utmhid,
        :utmp => page,
        :utmac => @utmac,
        :utmcc => @utmcc || cookie_params,
        :utmip => @utmip
      }

      # Add custom vars if present
      cvd = custom_var_data
      options[:utme] = cvd if /\w/ =~ cvd

      options
    end

    # Public: Record an event in Google Analytics
    # (http://code.google.com/apis/analytics/docs/gaJS/gaJSApiEventTracking.html)
    #
    # category  -
    # action    -
    # label     -
    # value     -
    # utmni     -
    # utmhid    -
    #
    # Example:
    #
    #   g = Gabba::Gabba.new("UT-1234", "mydomain.com")
    #   g.event("Videos", "Play", "ID", "123", true)
    #
    def event(category, action, label = nil, value = nil, utmni = false, utmhid = random_id)
      check_account_params
      hey(event_params(category, action, label, value, utmni, utmhid))
    end

    # Public: Renders event params data in the format needed for GA
    # Called before actually sending the data along to GA in Gabba#event
    def event_params(category, action, label = nil, value = nil, utmni = false, utmhid = false)
      raise ArgumentError.new("utmni must be a boolean") if (utmni.class != TrueClass && utmni.class != FalseClass)
      {
        :utmwv => @utmwv,
        :utmn => @utmn,
        :utmhn => @utmhn,
        :utmni => (1 if utmni), # 1 for non interactive event, excluded from bounce calcs
        :utmt => 'event',
        :utme => "#{event_data(category, action, label, value)}#{custom_var_data}",
        :utmcs => @utmcs,
        :utmul => @utmul,
        :utmhid => utmhid,
        :utmac => @utmac,
        :utmcc => @utmcc || cookie_params
      }
    end

    # Public: Renders event individual param data in the format needed for GA
    # Called before actually sending the data along to GA in Gabba#event
    def event_data(category, action, label = nil, value = nil)
      data = "5(#{category}*#{action}" + (label ? "*#{label})" : ")")
      data += "(#{value})" if value
      data
    end

    # Public:  Track an entire ecommerce transaction to Google Analytics in one call.
    # (http://code.google.com/apis/analytics/docs/gaJS/gaJSApiEcommerce.html#_gat.GA_Tracker_._trackTrans)
    #
    # order_id    - URL-encoded order ID (required). Maps to utmtid
    # total       - Order total (required). Maps to utmtto
    # store_name  - Affiliation or store name (default: nil). Maps to utmtst
    # tax         - Sales tax (default: nil). Maps to utmttx
    # shipping    - Shipping (default: nil). Maps to utmtsp
    # city        - City (default: nil). Maps to utmtci
    # region      - State or Provance (default: nil). Maps to utmtrg
    # country     - Country (default: nil). Maps to utmtco
    # utmhid      - String with the unique visitor id (default: random_id)
    #
    # Examples:
    #
    #   g = Gabba::Gabba.new("UT-1234", "mydomain.com")
    #   g.transaction("123456789", "1000.00")
    #
    #   g = Gabba::Gabba.new("UT-6666", "myawesomeshop.net")
    #   g.transaction("123456789", "1000.00", 'Acme Clothing', '1.29', '5.00', 'Los Angeles', 'California', 'USA')
    #
    def transaction(order_id, total, store_name = nil, tax = nil, shipping = nil, city = nil, region = nil, country = nil, utmhid = random_id)
      check_account_params
      hey(transaction_params(order_id, total, store_name, tax, shipping, city, region, country, utmhid))
    end

    # Public: Renders transaction params data in the format needed for GA
    # Called before actually sending the data along to GA in Gabba#transaction
    def transaction_params(order_id, total, store_name, tax, shipping, city, region, country, utmhid)
      {
        :utmwv => @utmwv,
        :utmn => @utmn,
        :utmhn => @utmhn,
        :utmt => 'tran',
        :utmcs => @utmcs,
        :utmul => @utmul,
        :utmhid => utmhid,
        :utmac => @utmac,
        :utmcc => @utmcc || cookie_params,
        :utmtid => order_id,
        :utmtst => store_name,
        :utmtto => total,
        :utmttx => tax,
        :utmtsp => shipping,
        :utmtci => city,
        :utmtrg => region,
        :utmtco => country
      }
    end

    # Public:  Track an item purchased in an ecommerce transaction to Google Analytics.
    # (http://code.google.com/apis/analytics/docs/gaJS/gaJSApiEcommerce.html#_gat.GA_Tracker_._addItem)
    def add_item(order_id, item_sku, price, quantity, name = nil, category = nil, utmhid = random_id)
      check_account_params
      hey(item_params(order_id, item_sku, name, category, price, quantity, utmhid))
    end

    # Public: Renders item purchase params data in the format needed for GA
    # Called before actually sending the data along to GA in Gabba#add_item
    def item_params(order_id, item_sku, name, category, price, quantity, utmhid)
      # '1234',           // utmtid URL-encoded order ID - required
      # 'DD44',           // utmipc SKU/code - required
      # 'T-Shirt',        // utmipn product name
      # 'Green Medium',   // utmiva category or variation
      # '11.99',          // utmipr unit price - required
      # '1'               // utmiqt quantity - required
      {
        :utmwv => @utmwv,
        :utmn => @utmn,
        :utmhn => @utmhn,
        :utmt => 'item',
        :utmcs => @utmcs,
        :utmul => @utmul,
        :utmhid => utmhid,
        :utmac => @utmac,
        :utmcc => @utmcc || cookie_params,
        :utmtid => order_id,
        :utmipc => item_sku,
        :utmipn => name,
        :utmiva => category,
        :utmipr => price,
        :utmiqt => quantity
      }
    end

    # Public: provide the user's __utma attribute from analytics cookie, allowing
    # better tracking of user flows
    #
    # Called before page_view etc
    #
    # Examples:
    #   g = Gabba::Gabba.new("UT-1234", "mydomain.com")
    #   g.identify_user(cookies[:__utma])
    #   g.page_view("something", "track/me")
    #
    def identify_user(options={})
      @utma = options[:utma] unless options[:utma].nil?
      @utmb = options[:utmb] unless options[:utmb].nil?
      @utmz = options[:utmz] unless options[:utmz].nil?
    end

    # create magical cookie params used by GA for its own nefarious purposes
    def cookie_params(utma1 = domain_hash(@utmhn), utma2 = rand(1147483647) + 1000000000, today = Time.now)
      if @utma.blank?
        @utma = "#{utma1}.#{utma2}.#{today.to_i}.#{today.to_i}.#{today.to_i}.1"
      end
      if @utmb.blank?
        @utmb = "#{utma1}.1.10.#{today.to_i}"
      end

      if @utmz.blank?
        @utmz = "#{utma1}.#{today.to_i}.1.1.utmcsr=(direct)|utmccn=(direct)|utmcmd=(none)"
      end
      "__utma=#{@utma};+__utmz=#{@utmz};"
    end

    # sanity check that we have needed params to even call GA
    def check_account_params
      raise NoGoogleAnalyticsAccountError unless @utmac
      raise NoGoogleAnalyticsDomainError unless @utmhn
    end

    # makes the tracking call to Google Analytics
    def hey(params)
      query = params.map {|k,v| "#{k}=#{URI.escape(v.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))}" }.join('&')

      response = Net::HTTP.start(GOOGLE_HOST) do |http|
        request = Net::HTTP::Get.new("#{BEACON_PATH}?#{query}")
        request["User-Agent"] = URI.escape(user_agent)
        request["Accept"] = "*/*"
        http.request(request)
      end

      raise GoogleAnalyticsNetworkError unless response.code == "200"
      response
    end

    def random_id
      rand 8999999999 + 1000000000
    end

    def escape(t)
      return t if !t || (/\w/ !~ t.to_s)

      t.to_s.gsub(/[\*'!\)]/) do |m|
        "'#{ESCAPES.index(m)}"
      end
    end
    def domain_hash(domain_name)
      return 1 if domain_name.blank?
      hash = 0
      length = domain_name.length
      pos = length -1
      while pos >= 0
        current = domain_name[pos].ord
        hash = ((hash << 6) & 0xfffffff) + current + (current << 14)
        left_most_7 = hash & 0xfe00000
        if left_most_7 != 0
          hash ^= left_most_7 >> 21
        end
        pos -= 1
      end
      return hash
    end
    def utmip_fetch(remote_ip)
      return '' if remote_ip.blank?
      # Capture the first three octects of the IP address and replace the forth
      # with 0, e.g. 124.455.3.123 becomes 124.455.3.0
      remote_ip.to_s.gsub(/([^.]+\.[^.]+\.[^.]+\.)[^.]+/,"\\1") + "0"
    end

  end # Gabba Class

end
