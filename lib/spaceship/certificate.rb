require 'openssl'

module Spaceship
  class Certificate < Base

    attr_accessor :id, :name, :status, :created, :expires, :owner_type, :owner_name, :owner_id, :type_display_id, :app
    attr_mapping({
      'certificateId' => :id,
      'name' => :name,
      'statusString' => :status,
      'dateCreated' => :created,
      'expirationDate' => :expires,
      'ownerType' => :owner_type,
      'ownerName' => :owner_name,
      'ownerId' => :owner_id,
      'certificateTypeDisplayId' => :type_display_id
    })

    # these certs are not associated with apps
    class Development < Certificate; end
    class Production < Certificate; end

    # all these certs have apps.
    class PushCertificate < Certificate; end # abstract class
    class DevelopmentPush < PushCertificate; end
    class ProductionPush < PushCertificate; end
    class WebsitePush < PushCertificate; end
    class VoIPPush < PushCertificate; end
    class Passbook < Certificate; end
    class ApplePay < Certificate; end

    CERTIFICATE_TYPE_IDS = {
      "5QPB9NHCEI" => Development,
      "R58UK2EWSO" => Production,
      "9RQEK7MSXA" => Certificate,
      "LA30L5BJEU" => Certificate,
      "BKLRAVXMGM" => DevelopmentPush,
      "3BQKVH9I2X" => ProductionPush,
      "Y3B2F3TYSI" => Passbook,
      "3T2ZP62QW8" => WebsitePush,
      "E5D663CMZW" => WebsitePush,
      "4APLUP237T" => ApplePay
    }

    #class methods
    class << self
      def certificate_signing_request
        key = OpenSSL::PKey::RSA.new 2048
        csr = OpenSSL::X509::Request.new
        csr.version = 0
        csr.subject = OpenSSL::X509::Name.new([
          ['CN', 'PEM', OpenSSL::ASN1::UTF8STRING]
        ])
        csr.public_key = key.public_key
        csr.sign(key, OpenSSL::Digest::SHA1.new)
        return [csr, key]
      end

      def factory(attrs)
        klass = CERTIFICATE_TYPE_IDS[attrs['certificateTypeDisplayId']]
        klass ||= Certificate
        klass.new(attrs)
      end

      ##
      # @param types
      def all
        if (self == Certificate) # are we the base-class?
          types = CERTIFICATE_TYPE_IDS.keys
        else
          types = [CERTIFICATE_TYPE_IDS.key(self)]
        end

        client.certificates(types).map do |cert|
          factory(cert)
        end
      end

      def find(certificate_id)
        all.find do |c|
          c.id == certificate_id
        end
      end

      def create!(csr, bundle_id = nil)
        type = CERTIFICATE_TYPE_IDS.key(self)

        # look up the app_id by the bundle_id
        if bundle_id
          app_id = Spaceship::App.find(bundle_id).app_id
        end

        # if this succeeds, we need to save the .cer and the private key in keychain access or wherever they go in linux
        response = client.create_certificate!(type, csr.to_pem, app_id)
        # munge the response to make it work for the factory
        response['certificateTypeDisplayId'] = response['certificateType']['certificateTypeDisplayId']
        self.new(response)
      end
    end

    # instance methods
    def download
      file = client.download_certificate(id, type_display_id)
      OpenSSL::X509::Certificate.new(file)
    end

    def revoke!
      client.revoke_certificate!(id, type_display_id)
    end

    def expires_at
      Time.parse(expires)
    end

    def is_push?
      # does display_type_id match push?
      [Client::ProfileTypes::Push.development, Client::ProfileTypes::Push.production].include?(type_display_id)
    end

  end
end