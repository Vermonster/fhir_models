require_relative "../simplecov"
require_relative '../../lib/fhir_models'

require 'fileutils'
require 'pry'
require 'minitest/autorun'
require 'bundler/setup'
require 'test/unit'

class XmlValidationTest < Test::Unit::TestCase
 
  # turn off the ridiculous warnings
  $VERBOSE=nil

  ERROR_DIR = File.join('errors', 'XmlValidationTest')
  EXAMPLE_ROOT = File.join('examples','xml')

  # Automatically generate one test method per example file
  example_files = File.join(EXAMPLE_ROOT, '**', '*.xml')

  # Create a blank folder for the errors
  FileUtils.rm_rf(ERROR_DIR) if File.directory?(ERROR_DIR)
  FileUtils.mkdir_p ERROR_DIR

  Dir.glob(example_files).each do | example_file |
    example_name = File.basename(example_file, ".xml")
    define_method("test_xml_validation_#{example_name}") do
      run_xml_validation_test(example_file, example_name)
    end
  end

  def run_xml_validation_test(example_file, example_name)
    input_xml = File.read(example_file)
    resource = FHIR::Xml.from_xml(input_xml)
    errors = resource.validate
    if !errors.empty?
      File.open("#{ERROR_DIR}/#{example_name}.err", 'w:UTF-8') {|file| file.write(JSON.pretty_unparse(errors))}
      File.open("#{ERROR_DIR}/#{example_name}.xml", 'w:UTF-8') {|file| file.write(input_xml)}      
    end
    assert errors.empty?, "Resource failed to validate."
  end

  def test_xml_is_valid
    filename = File.join(EXAMPLE_ROOT,'patient-example.xml')
    xml = File.read(filename)
    assert FHIR::Xml.is_valid?(xml), "XML failed to schema validate."
  end

  def test_resource_is_valid
    filename = File.join(EXAMPLE_ROOT,'patient-example.xml')
    xml = File.read(filename)
    resource = FHIR::Xml.from_xml(xml)
    assert resource.is_valid?, "Resource failed to validate."
  end

end
