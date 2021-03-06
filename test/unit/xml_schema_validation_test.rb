require_relative "../simplecov"
require_relative '../../lib/fhir_models'

require 'fileutils'
require 'pry'
require 'nokogiri/diff'
require 'minitest/autorun'
require 'bundler/setup'
require 'test/unit'

class XmlSchemaValidationTest < Test::Unit::TestCase
 
  # turn off the ridiculous warnings
  $VERBOSE=nil

  ERROR_DIR = File.join('errors', 'XmlSchemaValidationTest')
  EXAMPLE_ROOT = File.join('examples','xml')

  XSD_ROOT = File.join('definitions','schema')
  XSD = Nokogiri::XML::Schema(File.new(File.join(XSD_ROOT, "fhir-single.xsd")))

  # Automatically generate one test method per example file
  example_files = File.join(EXAMPLE_ROOT, '**', '*.xml')

  # Create a blank folder for the errors
  FileUtils.rm_rf(ERROR_DIR) if File.directory?(ERROR_DIR)
  FileUtils.mkdir_p ERROR_DIR
  
  Dir.glob(example_files).each do | example_file |
    example_name = File.basename(example_file, ".xml")
    define_method("test_xml_schema_validation_#{example_name}") do
      run_xml_schema_validation_test(example_file, example_name)
    end
  end

  def run_xml_schema_validation_test(example_file, example_name)
    input_xml = File.read(example_file)
    resource = FHIR::Xml.from_xml(input_xml)
    assert !resource.nil?

    output_xml = resource.to_xml
    assert output_xml.length > 0

    errors_input = XSD.validate(Nokogiri::XML(input_xml))
    errors_output = XSD.validate(Nokogiri::XML(output_xml))

    original_errors = false
    if (!errors_input.empty?)
      puts "  WARNING: validation errors in example: #{example_name}"
      if (errors_input.length == errors_output.length)
        errors_match = true
        (0...(errors_input.length)).each {|i| errors_match &&= (errors_output[i].message == errors_input[i].message)}
        original_errors = errors_match
      end
    end

    if !errors_output.empty? && !original_errors
      File.open("#{ERROR_DIR}/#{example_name}.err", 'w:UTF-8') do | file |
        file.write "#{example_name}: #{errors.length} errors\n\n"
        errors.each do |error|
          file.write(sprintf("%-8d  %s\n", error.line, error.message))
        end

        if !errors_input.empty?
          file.write("ORIGINAL ERRORS: ")
          errors_input.each do |error|
            file.write(sprintf("%-8d  %s\n", error.line, error.message))
          end
        end
      end
      File.open("#{ERROR_DIR}/#{example_name}_PRODUCED.xml", 'w:UTF-8') {|file| file.write(output_xml)}
      File.open("#{ERROR_DIR}/#{example_name}_ORIGINAL.xml", 'w:UTF-8') {|file| file.write(input_xml)}
    end

    assert errors_output.empty? || original_errors, "Schema Validation errors: \n #{errors_output.join('\n')}"
  end
end
