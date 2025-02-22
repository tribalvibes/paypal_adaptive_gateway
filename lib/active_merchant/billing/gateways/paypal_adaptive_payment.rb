dir = File.dirname(__FILE__)
require dir + '/paypal_adaptive_payments/exceptions.rb'
require dir + '/paypal_adaptive_payments/adaptive_payment_response.rb'
require dir + '/paypal_adaptive_payments/utils.rb'
require dir + '/paypal_adaptive_payments/version.rb'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PaypalAdaptivePaymentGateway < Gateway # :nodoc:
      
      include AdaptivePaymentResponses
      include AdaptiveUtils
      
      TEST_URL = 'https://svcs.sandbox.paypal.com/AdaptivePayments/'
      LIVE_URL = 'https://svcs.paypal.com/AdaptivePayments/'
      
      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['US']
      
      # The homepage URL of the gateway
      self.homepage_url = 'http://x.com/'
      
      # The name of the gateway
      self.display_name = 'Paypal Adaptive Payments'
      
      attr_accessor :config_path
      @config_path = "#{Rails.root}/config/paypal.yml"
      
      def initialize(options = {})
        @config = {}
        if options.empty?
          load_config
        else
          @config.merge! options
        end
      end 
      
      def pay(options)
        commit 'Pay', build_adaptive_payment_pay_request(options)
      end

      def execute_payment(options)
        commit 'ExecutePayment', build_adaptive_payment_execute_request(options)
      end
    
      def details_for_payment options
        commit 'PaymentDetails', build_adaptive_payment_details_request(options)
      end
      
      def refund options
        commit 'Refund', build_adaptive_refund_details(options)
      end

      # Send a preapproval request to pay pal
      #
      # ==== Options
      #
      # * +:end_date+ - _xs:datetime_ The ending date
      # * +:start_date+ - _xs:datetime_ The start date (defaults: current)
      # * +:max_amount+ - _xs:decimal_ The preapproved maximum total amount of all payments.
      # * +:currency_code+ - The currency code (defaults: USD)
      # * +:cancel_url+ - URL to redirect the sender’s browser to after canceling the preapproval
      # * +:return_url+ - URL to redirect the sender’s browser to after the sender has logged into PayPal and confirmed the preapproval
      # * +:notify_url+ - The URL to which you want all IPN messages for this preapproval to be sent. (Optional)
      #
      # To get more details on fields see +Paypal PreApproval API+ at https://www.x.com/docs/DOC-1419
      def preapprove_payment options
        commit 'Preapproval', build_preapproval_payment(options)
      end
      
      def preapproval_details_for options
        commit 'PreapprovalDetails', build_preapproval_details(options)
      end
      
      def convert_currency  options
        commit 'ConvertCurrency', build_currency_conversion(options)
      end
      
      #debug method, provides an easy to use debug method for the class
      def debug
        "Url: #{@url}\n\n JSON: #{@xml} \n\n Raw: #{@raw}"
      end
      
      private                       
      
      #loads config from default file if it is not provided to the constructor
      def load_config
        raise ConfigDoesNotExist if !File.exists?(@config_path);
        @config.merge! Yaml.load_file(@config_path)[Rails.env || RAILS_ENV].symbolize_keys!
      end
      
      def build_adaptive_payment_pay_request opts
        @xml = ''
        xml = Builder::XmlMarkup.new :target => @xml, :indent => 2
        xml.instruct!
        xml.PayRequest do |x|
          x.requestEnvelope do |x|
            x.detailLevel 'ReturnAll'
            x.errorLanguage opts[:error_language] ||= 'en_US'
          end
          x.actionType opts[:pay_primary] ? 'PAY_PRIMARY' : 'PAY'
          x.cancelUrl opts[:cancel_url]
          x.returnUrl opts[:return_url]
          if opts[:notify_url]
            x.ipnNotificationUrl opts[:notify_url]
          end
          x.trackingId opts[:tracking_id] if opts[:tracking_id]
          x.memo opts[:memo] if opts[:memo]
          x.pin opts[:pin] if opts[:pin]
          x.currencyCode opts[:currency_code] ||= 'USD'
          x.senderEmail opts[:senders_email] if opts[:senders_email]
          x.receiverList do |x|
            opts[:receiver_list].each do |receiver|
              x.receiver do |x|
                x.email receiver[:email]
                x.amount currency_to_two_places(receiver[:amount])
                x.primary receiver[:primary] if receiver[:primary]
                x.paymentType receiver[:payment_type] ||= 'GOODS'
                x.invoiceId receiver[:invoice_id] if receiver[:invoice_id]
              end
            end
          end
          x.feesPayer opts[:fees_payer] ||= 'EACHRECEIVER'
        end
      end

      def build_adaptive_payment_execute_request opts
        @xml = ''
        xml = Builder::XmlMarkup.new :target => @xml, :indent => 2
        xml.instruct!
        xml.ExecutePaymentRequest do |x|          
          x.requestEnvelope do |x|
            x.detailLevel 'ReturnAll'
            x.errorLanguage opts[:error_language] ||= 'en_US'
          end
          x.payKey opts[:paykey]
        end
      end
      
      def build_adaptive_payment_details_request opts
        @xml = ''
        xml = Builder::XmlMarkup.new :target => @xml, :indent => 2
        xml.instruct!
        xml.PayRequest do |x|          
          x.requestEnvelope do |x|
            x.detailLevel 'ReturnAll'
            x.errorLanguage opts[:error_language] ||= 'en_US'
          end
          x.payKey opts[:paykey]
        end
      end
      
      def build_adaptive_refund_details options
        @xml = ''
        xml = Builder::XmlMarkup.new :target => @xml, :indent => 2
        xml.instruct!
        xml.RefundRequest do |x|
          x.requestEnvelope do |x|
            x.detailLevel 'ReturnAll'
            x.errorLanguage options[:error_language] ||= 'en_US'
          end
          x.actionType 'REFUND'
          if options[:pay_key]
            x.payKey options[:pay_key]
          end
          if options[:transaction_id]
            x.payKey options[:transaction_id]
          end
          if options[:tracking_id]
            x.trackingId options[:tracking_id]
          end
          x.currencyCode options[:currency_code] ||= 'USD'
          x.receiverList do |x|
            options[:receiver_list].each do |receiver|
              x.receiver do |x|
                x.amount receiver[:amount]
                x.paymentType receiver[:payment_type] ||= 'GOODS'
                x.invoiceId receiver[:invoice_id] if receiver[:invoice_id]
                x.email receiver[:email]
                
              end
            end
          end
        end
      end
      
      def build_preapproval_payment options
        opts = {
          :currency_code => "USD",
          :start_date => DateTime.current
        }.update(options)
        
        @xml = ''
        xml = Builder::XmlMarkup.new :target => @xml, :indent => 2
        xml.instruct!
        xml.PreapprovalRequest do |x|
          # request envelope
          x.requestEnvelope do |x|
            x.detailLevel 'ReturnAll'
            x.errorLanguage opts[:error_language] ||= 'en_US'
          end
          
          # required preapproval fields
          x.endingDate opts[:end_date].strftime("%Y-%m-%dT%H:%M:%S%Z")
          x.startingDate opts[:start_date].strftime("%Y-%m-%dT%H:%M:%S%Z")
          x.maxTotalAmountOfAllPayments opts[:max_amount]
          x.currencyCode opts[:currency_code]
          x.cancelUrl opts[:cancel_url]
          x.returnUrl opts[:return_url]

          #optional preapproval fields
          x.maxAmountPerPayment opts[:max_amount_per_payment] unless opts[:max_amount_per_payment].blank?
          x.maxNumberOfPayments opts[:max_number_of_payments] unless opts[:max_number_of_payments].blank?
          x.memo opts[:memo] unless opts[:memo].blank?

          
          # notify url
          if opts[:notify_url]
            x.ipnNotificationUrl opts[:notify_url]
          end
        end
      end
      
      def build_preapproval_details options
        @xml = ''
        xml = Builder::XmlMarkup.new :target => @xml, :indent => 2
        xml.instruct!
        xml.PreapprovalDetailsRequest do |x|
          x.requestEnvelope do |x|
            x.detailLevel 'ReturnAll'
            x.errorLanguage opts[:error_language] ||= 'en_US'
          end
          x.preapprovalKey options[:preapproval_key]
          x.getBillingAddress options[:get_billing_address] if options[:get_billing_address]
        end
      end
      
      def build_currency_conversion options
        @xml = ''
        xml = Builder::XmlMarkup.new :target => @xml, :indent => 2
        xml.instruct!
        xml.ConvertCurrencyRequest do |x|
          x.requestEnvelope do |x|
            x.detailLevel 'ReturnAll'
            x.errorLanguage opts[:error_language] ||= 'en_US'
          end
          x.baseAmountList do |x|
            x.currency do |x|
              x.amount options[:amount]
              x.code options[:currency_code] ||= 'USD'
            end
          end
          x.convertoToCurrencyList do |x|
            options[:currencies].each do |currency|
              x.currency currency
            end
          end
        end
      end
      
      def parse json
        @raw = json
        resp = JSON.parse json
        if resp['responseEnvelope']['ack'] == 'Failure'
          error = AdaptivePaypalErrorResponse.new(resp)
          raise PaypalAdaptivePaymentsApiError.new(error)
        else
          AdaptivePaypalSuccessResponse.new(resp)
        end
      end     
      
      def commit(action, data)
        @response = parse(post_through_ssl(action, data))
      end
      
      def post_through_ssl(action, parameters = {})
        headers = {
          "X-PAYPAL-REQUEST-DATA-FORMAT" => "XML",
          "X-PAYPAL-RESPONSE-DATA-FORMAT" => "JSON",
          "X-PAYPAL-SECURITY-USERID" => @config[:login],
          "X-PAYPAL-SECURITY-PASSWORD" => @config[:password],
          "X-PAYPAL-SECURITY-SIGNATURE" => @config[:signature],
          "X-PAYPAL-APPLICATION-ID" => @config[:appid]
        }
        url action
        request = Net::HTTP::Post.new(@url.path)
        request.body = @xml
        headers.each_pair { |k,v| request[k] = v }
        request.content_type = 'text/xml'
        server = Net::HTTP.new(@url.host, 443)
        server.use_ssl = true
        server.verify_mode = OpenSSL::SSL::VERIFY_NONE
        server.start { |http| http.request(request) }.body
      end
      
      def endpoint_url
        test? ? TEST_URL : LIVE_URL
      end
      
      def test?
        Base.gateway_mode == :test
      end
      
      def url action
        @url = URI.parse(endpoint_url + action)
      end
      
    end
  end
end
