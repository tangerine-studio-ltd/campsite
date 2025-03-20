module ActionController
    module RequestForgeryProtection
      private
        def valid_request_origin?
          if request.origin.present?
            http_origin = request.origin.sub('https:', 'http:')
            https_origin = request.origin.sub('http:', 'https:')
            [http_origin, https_origin].include?(request.base_url)
          end
        end
    end
  end