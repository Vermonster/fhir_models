module FHIR
  class Model

    def initialize(hash={})
      self.from_hash(hash)
      self.class::METADATA.each do |key, value|
        if value['max'] > 1 && self.instance_variable_get("@#{key}").nil?
          self.instance_variable_set("@#{key}".to_sym, [])
        end
      end
    end

    def method_missing(method, *args, &block)
      if defined?(self.class::MULTIPLE_TYPES) && self.class::MULTIPLE_TYPES[method.to_s]
        self.class::MULTIPLE_TYPES[method.to_s].each do |type|
          type[0] = type[0].upcase
          value = self.method("#{method}#{type}").call()
          return value if !value.nil?
        end
        return nil
      elsif !@extension.empty?
        ext = @extension.select do |x|
          name = x.url.gsub('-','_').split('/').last
          anchor = name.split('#').last
          (method.to_s==name || method.to_s==anchor)
        end
        if !ext.first.nil?
          if !ext.first.value.nil?
            return ext.first.value 
          else
            return ext.first
          end
        end
      elsif !@modifierExtension.empty?
        ext = @modifierExtension.select do |x|
          name = x.url.gsub('-','_').split('/').last
          anchor = name.split('#').last
          (method.to_s==name || method.to_s==anchor)
        end
        if !ext.first.nil?
          if !ext.first.value.nil?
            return ext.first.value 
          else
            return ext.first
          end
        end
      end
      super(method, *args, &block)
    end

    def to_reference
      FHIR::Reference.new(reference: "#{self.class.name.demodulize}/#{self.id}")
    end

    def equals?(other, exclude=[])
      (self.class::METADATA.keys - exclude).each do |attribute|
        return false unless compare_attribute(self.instance_variable_get("@#{attribute}".to_sym), other.instance_variable_get("@#{attribute}".to_sym), exclude)
      end
      true
    end

    def mismatch(other, exclude=[])
      misses = []
      (self.class::METADATA.keys - exclude).each do |key|
        these = attribute_mismatch(self.instance_variable_get("@#{key}".to_sym), other.instance_variable_get("@#{key}".to_sym), exclude)
        if !these || (these.is_a?(Array) && !these.empty?)
          misses << "#{self.class}::#{key}"
          misses.concat these if these.is_a?(Array)
        end
      end
      misses
    end

    def attribute_mismatch(left, right, exclude=[])
      if left.respond_to?(:mismatch) && right.respond_to?(:mismatch)
        left.mismatch right, exclude
      else
        compare_attribute(left, right, exclude)
      end
    end

    def compare_attribute(left, right, exclude=[])
      if left.respond_to?(:equals?) && right.respond_to?(:equals?)
        left.equals? right, exclude
      elsif left.is_a?(Array) && right.is_a?(Array) && (left.length == right.length)
        result = true
        (0...(left.length)).each {|i| result &&= compare_attribute(left[i], right[i], exclude)}
        result
      else
        left == right
      end
    end

    def is_valid?
      validate.empty?
    end

    def validate(contained=nil)
      metadata = self.class::METADATA
      contained_here = [ self.instance_variable_get("@contained".to_sym) ].flatten
      contained_here << contained
      contained_here = contained_here.flatten.compact
      errors = {}
      metadata.each do |field,meta|
        errors[field] = []
        local_name = meta['local_name'] || field
        value = [ self.instance_variable_get("@#{local_name}".to_sym) ].flatten.compact
        # check cardinality
        count = value.length
        if !( count>=meta['min'] && count<=meta['max'] )
          errors[field] << "#{meta['path']}: invalid cardinality. Found #{count} expected #{meta['min']}..#{meta['max']}"
        end
        # check datatype
        datatype = meta['type']
        value.each do |v|
          klassname = v.class.name.gsub('FHIR::','')
          # if the data type is a generic Resource, validate it
          if datatype=='Resource'
            if FHIR::RESOURCES.include?(klassname)
              validation = v.validate(contained_here)
              errors[field] << validation if !validation.empty?
            else
              errors[field] << "#{meta['path']}: incorrect type. Found #{klassname} expected #{datatype}"
            end
          # if the data type is a Reference, validate it, but also check the
          # type_profiles metadata. For example, if it should be a Reference(Patient)
          elsif datatype=='Reference'
            if klassname=='Reference'
              validation = v.validate(contained_here)
              errors[field] << validation if !validation.empty?
              if v.reference && meta['type_profiles']
                matches_one_profile = false
                meta['type_profiles'].each do |p|
                  p = p.split('/').last
                  matches_one_profile = true if v.reference.include?(p)
                end
                matches_one_profile = true if meta['type_profiles'].include?('http://hl7.org/fhir/StructureDefinition/Resource')
                if !matches_one_profile && v.reference.start_with?('#')
                  # we need to look at the local contained resources
                  r = contained_here.select{|x|x.id==v.reference[1..-1]}.first
                  if !r.nil?
                    meta['type_profiles'].each do |p|
                      p = p.split('/').last
                      matches_one_profile = true if r.resourceType==p
                    end
                  end
                end
                errors[field] << "#{meta['path']}: incorrect Reference type, expected #{meta['type_profiles'].map{|x|x.split('/').last}.join('|')}" if !matches_one_profile
              end
            else
              errors[field] << "#{meta['path']}: incorrect type. Found #{klassname} expected #{datatype}"
            end
          # if the data type is a particular resource or complex type
          elsif (FHIR::RESOURCES.include?(datatype) || FHIR::TYPES.include?(datatype))
            if datatype==klassname
              validation = v.validate(contained_here)
              errors[field] << validation if !validation.empty?
            else
              errors[field] << "#{meta['path']}: incorrect type. Found #{klassname} expected #{datatype}"
            end
          # if the data type is a primitive, test the regular expression (if any)
          elsif FHIR::PRIMITIVES.include?(datatype)
            primitive_meta = FHIR::PRIMITIVES[datatype]
            if primitive_meta['regex'] && primitive_meta['type']!='number'
              match = (v =~ Regexp.new(primitive_meta['regex']))
              errors[field] << "#{meta['path']}: #{v} does not match #{datatype} regex" if match.nil?
            else
              errors[field] << "#{meta['path']}: #{v} is not a valid #{datatype}" if !is_primitive?(datatype,v)
            end
          end
          # check binding
          if meta['binding']
            if meta['binding']['strength']=='required'
              the_codes = [ v ]
              if meta['type']=='Coding'
                the_codes = [ v.code ]
              elsif meta['type']=='CodeableConcept'
                the_codes = v.coding.map{|c|c.code}.compact
              end
              has_valid_code = false
              if meta['valid_codes']
                meta['valid_codes'].each do |key,codes|
                  has_valid_code = true if !(codes&the_codes).empty?
                  break if has_valid_code
                end
              else
                the_codes.each do |code|
                  has_valid_code = true if check_binding(meta['binding']['uri'],code)
                  break if has_valid_code
                end
              end
              errors[field] << "#{meta['path']}: invalid codes #{the_codes}" if !has_valid_code
            end
          end
        end # value.each
        errors.delete(field) if value.empty?
      end # metadata.each
      # check multiple types
      multiple_types = self.class::MULTIPLE_TYPES rescue {}
      multiple_types.each do |prefix,suffixes|
        count = 0
        suffixes.each do |suffix|
          count += 1 if errors["#{prefix}#{suffix}"]
        end
        errors[prefix] = ["#{prefix}[x]: more than one type present."] if(count > 1)
      end
      errors.keep_if{|k,v|(v && !v.empty?)}
    end

    def is_primitive?(datatype,value)
      # Remaining data types: handle special cases before checking type StructureDefinitions
      return case datatype.downcase
      when 'boolean'
        value==true || value==false || value.downcase=='true' || value.downcase=='false'
      when 'code'
        value.is_a?(String) && value.size>=1 && value.size==value.rstrip.size
      when 'string', 'markdown'
        value.is_a?(String)
      when 'xhtml'
        fragment = Nokogiri::HTML::DocumentFragment.parse(value)
        value.is_a?(String) && fragment.errors.size == 0
      when 'base64binary'
        regex = /[^0-9\+\/\=A-Za-z\r\n ]/
        value.is_a?(String) && (regex =~ value).nil?
      when 'uri'
        !URI.parse(value).nil? rescue false
      when 'instant'
        regex = /\A[0-9]{4}(-(0[1-9]|1[0-2])(-(0[0-9]|[1-2][0-9]|3[0-1])(T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z|(\+|-)((0[0-9]|1[0-3]):[0-5][0-9]|14:00)))))\Z/
        value.is_a?(String) && !(regex =~ value).nil?
      when 'integer','unsignedint'
        (!Integer(value).nil? rescue false)
      when 'positiveint'
        (!Integer(value).nil? rescue false) && (Integer(value) >= 0)
      when 'decimal'
        (!Float(value).nil? rescue false)
      else
        $LOG.warn "Unable to check #{value} for datatype #{datatype}"
      end
    end

    def check_binding(uri,value)
      valid = false
      if uri=='http://hl7.org/fhir/ValueSet/content-type' || uri=='http://www.rfc-editor.org/bcp/bcp13.txt'
        matches = MIME::Types[value]
        json_or_xml = value.downcase.include?('xml') || value.downcase.include?('json')
        known_weird = ['application/cql+text'].include?(value)
        valid = json_or_xml || known_weird || (!matches.nil? && !matches.empty?)
      elsif uri=='http://tools.ietf.org/html/bcp47'
        hasRegion = (!(value =~ /-/).nil?)
        valid = !BCP47::Language.identify(value.downcase).nil? && (!hasRegion || !BCP47::Region.identify(value.upcase).nil?)
      else
        $LOG.warn "Unable to check_binding on unknown ValueSet: #{uri}"
      end
      valid
    end

    private :is_primitive?, :check_binding

  end
end
