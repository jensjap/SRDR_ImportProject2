## encoding: UTF-8

require 'nokogiri'
require_relative "trollop"

## This program reads in an html document and extract data to be
## inserted into a SRDR project
##
## Author::    Jens Jap  (mailto:jens_jap@brown.edu)
## Copyright::
## License::   Distributes under the same terms as Ruby

def load_rails_environment
    ENV["RAILS_ENV"] = ARGV.first || ENV["RAILS_ENV"] || "development"
    require File.expand_path(File.dirname(__FILE__) + "./../SRDR/config/environment")
end

# Minimal arg parser
# http://trollop.rubyforge.org/
opts = Trollop::options do
    opt :file,            "Filename",              :type => :string
    opt :project_id,      "Project ID",            :type => :integer
    opt :creator_id,      "Creator ID",            :type => :integer, :default => 1
    opt :dry_run,         "Dry-run. No database modifications take place"
    opt :analyze,         "Run the crawler and display statistical summary"
end

# Ensures that required arguments have been received
# Options hash -> Boolean
def validate_arg_list(opts)
    Trollop::die :file,            "Missing file name"                 unless opts[:file_given]
    Trollop::die :project_id,      "You must supply a project id"      unless opts[:project_id_given]
end

# Strips the text from any new line and tabs
# String -> String
def clean_text(s)
    s.strip.gsub(/\n\t/, " ").gsub(/\t/, "").gsub("  ", " ")
end

# Looks for `table' tags in the document and retrieves them
# using nokogiri parser
# file -> Nokogiri
def parse_html_file(opts)
    f = File.open(opts[:file])
    Nokogiri::HTML(f)
end

def get_table_data(doc)
    tables = Array.new

    # ELIGIBILITY CRITERIA AND OTHER CHARACTERISTICS
    table = doc.xpath("/html/body/p//*[contains(text(), 'ELIGIBILITY\nCRITERIA AND OTHER CHARACTERISTICS')]")[0]
    if table.nil?
        table = doc.xpath("//html/body//*[contains(text(), 'ELIGIBILITY')]/following-sibling::table[1]")
    else
        table = table.xpath("./ancestor::p[1]/following-sibling::table[1]")
    end
    table = split_table_data(table)
    tables << (table)

    table_names = ["POPULATION\n(BASELINE)",
                   "Background\nDiet",
                   "INTERVENTION(S),\nSKIP IF OBSERVATIONAL STUDY",
                   "LIST\nOF ALL OUTCOMES",
    ]
    #table_names = ["ELIGIBILITY",
    #               "POPULATION",
    #               "Background",
    #               "INTERVENTION(S)",
    #               "LIST",
    #]

    table_names.each do |name|
        table = doc.xpath("/html/body//*[contains(text(), '#{name}')]/ancestor::p[1]/following-sibling::table[1]")
        table = split_table_data(table)
        tables << table
    end

    ## 2 ARMS/GROUPS: DICHOTOMOUS OUTCOMES (e.g. OR, RR, %death)
    #table = doc.xpath("/html/body/p//*[contains(text(), 'DICHOTOMOUS OUTCOMES')]")[0]
    #table = table.xpath("./ancestor::p[1]/following-sibling::table[1]")
    #table = split_table_data(table)
    #tables << (table)

    ## 2 ARMS/GROUPS: CONTINOUS OUTCOMES (e.g. BMD, BP)
    #table = doc.xpath("/html/body/p//*[contains(text(), 'CONTINOUS OUTCOMES')]")
    #table = table.xpath("./ancestor::p[1]/following-sibling::table[1]")
    #table = split_table_data(table)
    #tables << (table)

    ## ≥2 ARMS/GROUPS: DICHOTOMOUS OUTCOMES (e.g. OR, RR, %death)
    #table = doc.xpath("/html/body/p//*[contains(text(), 'DICHOTOMOUS OUTCOMES')]")[1]
    #table = table.xpath("./ancestor::p[1]/following-sibling::table[1]")
    #table = split_table_data(table)
    #tables << (table)

    ## ≥2 ARMS/GROUPS: CONTINOUS OUTCOMES (e.g. BMD, BP)
    #table = doc.xpath("/html/body/p//*[contains(text(), 'CONTINOUS OUTCOMES')]")[1]
    #table = table.xpath("./ancestor::p[1]/following-sibling::table[1]")
    #table = split_table_data(table)
    #tables << (table)

    # "MEAN\nDATA. THIS SHOULD ONLY APPLY TO CASE-COHORT STUDIES"
    table = doc.xpath("/html/body/p//*[contains(text(), 'MEAN\nDATA. THIS SHOULD ONLY APPLY TO CASE-COHORT STUDIES')]/ancestor::p[1]/following-sibling::table[1]")
    table = split_table_data(table)
    tables << table

    # "OTHER RESULTS"
    table = doc.xpath("/html/body/p//*[contains(text(), 'OTHER\nRESULTS')]/ancestor::p[1]/following-sibling::table[1]")
    table = split_table_data(table)
    tables << table

    # "QUALITY of INTERVENTIONAL STUDIES"
    table = doc.xpath("/html/body/p//*[contains(text(), 'QUALITY\nof INTERVENTIONAL STUDIES')]/ancestor::p[1]/following-sibling::table[1]")
    table = split_table_data(table)
    tables << table

    # "QUALITY of COHORT OR NESTED CASE-CONTROL STUDIES"
    table = doc.xpath("/html/body/p//*[contains(text(), 'QUALITY\nof COHORT OR NESTED CASE-CONTROL STUDIES')]/ancestor::p[1]/following-sibling::table[1]")
    table = split_table_data(table)
    tables << table

    # Comments
    table = doc.xpath('/html/body/table//td//*[contains(text(), "Comments")]')[0].xpath('./ancestor::table[1]')
    table = split_table_data(table)
    tables << table

    # Comments for results
    table = doc.xpath('/html/body/table//td//*[contains(text(), "Comments")]')[1].xpath('./ancestor::table[1]')
    table = split_table_data(table)
    tables << table

    # Confounders
    table = doc.xpath('/html/body//*[contains(text(), "----Confounders:")]/ancestor::p[1]/following-sibling::table[1]')
    table = split_table_data(table)
    #p table
    #gets
    #table.each do |t|
    #    p t
    #end
    tables << table


    return tables
end

# Find table row elements out of Nokogiri type object and packages them up
# into an array
# Nokogiri -> Array
def split_table_data(table)
    temp = Array.new
    rows = table.xpath('.//tr')
    rows.each do |row|
        temp << convert_to_array(row)
    end
    return temp
end

# Helper to get_table_data function. Does the same procedure but at the row
# level by cutting the row into the table data elements (columns) and packaging
# them up into an array
# Nokogiri -> Array
def convert_to_array(row_data)
    temp = Array.new
    rows = row_data.xpath('./td')
    rows.each do |row|
        temp << clean_text(row.text())
    end
    return temp
end

# Creates an entry in `studies' table
# Options Hash -> Study
def create_study(opts)
    Study.create(project_id: opts[:project_id],
                 creator_id: opts[:creator_id])
end

# Associates key questions to study by inserting into `study_key_questions' table
def add_study_to_key_questions_association(key_question_id_list, study)
    key_question_id_list.each do |n|
        StudyKeyQuestion.create(study_id: study.id,
                                key_question_id: n,
                                extraction_form_id: 194)
    end
end

# Associates key questions to study by inserting into `study_key_questions' table
# Only when Quality Of Interventional Studies exists
def add_study_to_key_questions_association_qoi(study)
    StudyKeyQuestion.create(study_id: study.id,
                            key_question_id: 361,
                            extraction_form_id: 190)
    StudyExtractionForm.create(study_id: study.id,
                               extraction_form_id: 190)
end

# Associates key questions to study by inserting into `study_key_questions' table
# Only when Quality Of Cohort Or Nested Case-Control Studies exists
def add_study_to_key_questions_association_qoc(study)
    StudyKeyQuestion.create(study_id: study.id,
                            key_question_id: 362,
                            extraction_form_id: 193)
    StudyExtractionForm.create(study_id: study.id,
                               extraction_form_id: 193)
end

# Associates study to extraction form by inserting into `study_extraction_forms' table
def add_study_to_extraction_form_association(study)
    StudyExtractionForm.create(study_id: study.id,
                               extraction_form_id: 194)
end

# Determines if quality of interventional studies table has any entries
# QualityOfInterventionalStudiesTableArray -> Boolean
def quality_of_interventional_studies?(q)
    # First row are the headers. We need to look at the first element of the next row
    row = q[1]
    # Return false if it is blank, else true
    row[0].blank? ? false : true
end

# Determines if quality of cohort or nested case control studies table has any entries
# QualityOfCohortOrNestedCaseControlStudiesTableArray -> Boolean
def quality_of_cohort_or_nested_case_control_studies?(q)
    # First row are the headers. We need to look at the first element of the next row
    row = q[1]
    # Return false if it is blank, else true
    row[0].blank? ? false : true
end

# Inserts publication information for this study
# Study EligibilityTableArray -> nil
def insert_publication_information(study, eligibility)
    internal_id = eligibility[1][0]
    pp = PrimaryPublication.create(study_id: study.id,
                                   title: nil,
                                   author: nil,
                                   country: nil,
                                   year: nil,
                                   pmid: nil,
                                   journal: nil,
                                   volume: nil,
                                   issue: nil,
                                   trial_title: nil)
    PrimaryPublicationNumber.create(primary_publication_id: pp.id,
                                    number: internal_id,
                                    number_type: "internal")
end

# Uses the eligibility table to retrieve the UI value. The UI value corresponds to Pubmed IDs
# EligibilityTableArray -> Natural
def retrieve_pmid_from_eligibility_table(eligibility)
    # Skip the header row
    first_data_row = eligibility[1]

    # UI column
    first_data_row[0]
end

# Helper to translate short answers to full length
def trans_yes_no_nd(s)
    s = "nd" if s.blank?
    t = {"y" => "Yes",
         "yes" => "Yes",
         "n" => "No",
         "no" => "No",
         "nd" => "nd",
         "na" => "Not Applicable"}
    t[s.downcase] || s unless s.blank?
end

def add_quality_dimension_data_points_qoi(quality_interventional, study)
    row = quality_interventional[1]
    adverse_event_value = quality_interventional[2][1]
    explanation = quality_interventional[3][1]
    fields = QualityDimensionField.find(:all, :order => "id", :conditions => { :extraction_form_id => 190 })
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[0].id,  # appropriate randomization
        value: trans_yes_no_nd(row[3]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[1].id,  # allocation concealment
        value: trans_yes_no_nd(row[4]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[2].id,  # dropout rate < 20%
        value: trans_yes_no_nd(row[6]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[3].id,  # blinded outcome
        value: trans_yes_no_nd(row[7]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[4].id,  # intention to treat
        value: trans_yes_no_nd(row[8]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[5].id,  # appropriate statistical analysis
        value: trans_yes_no_nd(row[9]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[6].id,  # assessment for confounding
        value: trans_yes_no_nd(row[10]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[7].id,  # clear reporting
        value: trans_yes_no_nd(row[11]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[8].id,  # appropriate washout period
        value: trans_yes_no_nd(row[5]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[9].id,  # design
        value: trans_yes_no_nd(row[2]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[10].id,  # adverse events
        value: trans_yes_no_nd(adverse_event_value),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[11].id,  # overall grade
        value: row[12],
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[12].id,  # explanation
        value: explanation,
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
end

def add_quality_dimension_data_points_qoc(quality_case_control_studies, study)
    overall_grade = quality_case_control_studies[4][1]
    explanation = quality_case_control_studies[5][1]
    row1 = quality_case_control_studies[1]
    row2 = quality_case_control_studies[2]
    row3 = quality_case_control_studies[3]
    fields = QualityDimensionField.find(:all, :order => "id", :conditions => { :extraction_form_id => 193 })
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[0].id,  # eligibility criteria clear
        value: trans_yes_no_nd(row1[3]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[2].id,  # exposure assessor blinded
        value: trans_yes_no_nd(row1[5]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[4].id,  # method reported
        value: trans_yes_no_nd(row1[7]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[7].id,  # one of the prespecified methods
        value: trans_yes_no_nd(row1[9]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[9].id,  # level of the exposure
        value: trans_yes_no_nd(row1[11]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[10].id,  # adjusted or matched
        value: trans_yes_no_nd(row1[13]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[12].id,  # clear definition
        value: trans_yes_no_nd(row1[15]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[15].id,  # prospective collection
        value: trans_yes_no_nd(row1[17]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
#########################################
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[1].id,  # sampling of population
        value: trans_yes_no_nd(row2[1]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[3].id,  # outcome assessor
        value: trans_yes_no_nd(row2[3]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[5].id,  # food composition database
        value: trans_yes_no_nd(row2[5]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[8].id,  # time from sample
        value: trans_yes_no_nd(row2[7]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[13].id,  # loss to follow up
        value: trans_yes_no_nd(row2[9]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[16].id,  # analysis was planned
        value: trans_yes_no_nd(row2[11]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
#########################################
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[6].id,  # internal calibration
        value: trans_yes_no_nd(row3[5]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[11].id,  # justification
        value: trans_yes_no_nd(row3[11]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[14].id,  # do the authors specify
        value: trans_yes_no_nd(row3[13]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[17].id,  # justification of sample size
        value: trans_yes_no_nd(row3[15]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
#########################################
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[18].id,  # overall grade
        value: overall_grade,
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[19].id,  # explanation
        value: explanation,
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
end

# Inserts design detail data points into `design_detail_data_points' table
def insert_design_detail_data(study, eligibility, background)
    eligibility_data_row = eligibility[1]
    background_first_row = background[1]
    background_second_row = background[2]
    design_details_qs = DesignDetail.find(:all, :order => "question_number", :conditions => { extraction_form_id: 194 })
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[0].id,  # study design
                                 value: trans_yes_no_nd(eligibility_data_row[2]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[1].id,  # inclusion
                                 value: trans_yes_no_nd(eligibility_data_row[3]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[2].id,  # exclusion
                                 value: trans_yes_no_nd(eligibility_data_row[4]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[3].id,  # enrollment years
                                 value: trans_yes_no_nd(eligibility_data_row[5]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[4].id,  # trial or cohort
                                 value: trans_yes_no_nd(eligibility_data_row[6]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[5].id,  # funding source
                                 value: trans_yes_no_nd(eligibility_data_row[7]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[6].id,  # extractor
                                 value: trans_yes_no_nd(eligibility_data_row[8]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
############################################################################
############################################################################
    # 25(OH)D and/or
    DesignDetailDataPoint.create(design_detail_field_id: 1927,
                                 value: trans_yes_no_nd(background_first_row[6]),  # biomarker assay
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8678,
                                 column_field_id: 8683,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1927,
                                 value: trans_yes_no_nd(background_first_row[7]),  # analytical validity
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8678,
                                 column_field_id: 8684,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1927,
                                 value: trans_yes_no_nd(background_first_row[8]),  # time between
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8678,
                                 column_field_id: 8685,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1927,
                                 value: trans_yes_no_nd(background_first_row[9]),  # season/date
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8678,
                                 column_field_id: 8686,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1927,
                                 value: trans_yes_no_nd(background_first_row[10]),  # background exposure
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8678,
                                 column_field_id: 8687,
                                 arm_id: 0,
                                 outcome_id: 0)
############################################################################
############################################################################
    # dietary calcium intake
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[3]),  # dietary assessment method
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8663,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[4]),  # food composition
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8664,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[5]),  # internal calibration
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8665,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[6]),  # biomarker assay
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8666,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[7]),  # analytical validity
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8667,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[9]),  # season/date
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8668,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[10]),  # background
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8669,
                                 arm_id: 0,
                                 outcome_id: 0)
end

# Test if 1st cell in intervention table is a number
# InterventionalTableArray -> Boolean
def interventions?(intervention)
    intervention[1][0].blank?
end

# Finds all arms for this study and attempts to make references to
# arms already created for this project. There are only 4 default
# to choose from atm; there might be more types of arms
# Study InterventionalTableArray -> nil
def create_arms(study, intervention)
    data_rows = intervention[1..-3]
    data_rows.each do |row|
        Arm.create(study_id: study.id,
                   title: row[2],
                   description: "",
                   display_number: Arm.find(:all, :conditions => { :study_id => study.id, :extraction_form_id => 194 }).length + 1,
                   extraction_form_id: 194,
                   is_suggested_by_admin: 0,
                   is_intention_to_treat: 1)
    end
end

# Inserts arm detail data points
# Study InterventionalTableArray -> nil
# !!!
def insert_arm_detail_data(study, intervention)
    co_interventions = trans_yes_no_nd(intervention[-2][1])
    compliance_adherence = trans_yes_no_nd(intervention[-1][1])
    intervention_data = intervention[1..-3]

    arms = Arm.find(:all, :conditions => { :study_id => study.id, :extraction_form_id => 194 })
    arm_details = ArmDetail.find(:all, :order => "question_number",
                                 :conditions => { :extraction_form_id => 194 })

    arms.each_with_index do |arm, n|
        arm_details.each_with_index do |arm_detail, m|
            ArmDetailDataPoint.create(arm_detail_field_id: arm_detail.id,
                                      value: trans_yes_no_nd(intervention_data[n][m+3]),
                                      notes: nil,
                                      study_id: study.id,
                                      extraction_form_id: 194,
                                      arm_id: arm.id,
                                     )
        end
        ArmDetailDataPoint.create(arm_detail_field_id: arm_details[-2].id,
                                  value: co_interventions,
                                  notes: nil,
                                  study_id: study.id,
                                  extraction_form_id: 194,
                                  arm_id: arm.id,
                                 )
        ArmDetailDataPoint.create(arm_detail_field_id: arm_details[-1].id,
                                  value: compliance_adherence,
                                  notes: nil,
                                  study_id: study.id,
                                  extraction_form_id: 194,
                                  arm_id: arm.id,
                                 )
    end
end

# Inserts baselineline characteristics. We are placing all values into All Arms (Total)
def insert_baseline_characteristics(study, population)
    baseline_characteristics = BaselineCharacteristic.find(:all,
                                                           :order => "question_number",
                                                           :conditions => { :extraction_form_id => 194 })
    baseline_characteristics.each_with_index do |baseline, n|
        BaselineCharacteristicDataPoint.create(
            baseline_characteristic_field_id: baseline.id,
            value: trans_yes_no_nd(population[1][n+3]),
            notes: nil,
            study_id: study.id,
            extraction_form_id: 194,
            arm_id: 0,
            subquestion_value: nil,
            row_field_id: 0,
            column_field_id: 0,
            outcome_id: 0,
            diagnostic_test_id: 0
        )
    end
end

# Attempts to find all outcomes for this study and create an entry in `outcomes' table
def create_outcomes(study, outcomes)
    outcomes[1..-1].each_with_index do |outcome|
        unless outcome[2].blank?
            o = Outcome.create(
                study_id: study.id,
                title: outcome[3],
                is_primary: 1,
                units: "",
                description: outcome[2],
                notes: "",
                outcome_type: "Continuous",
                extraction_form_id: 194
            )
            OutcomeTimepoint.create(
                outcome_id: o.id,
                number: "N/A",
                time_unit: "years"
            )
        end
    end
end

def insert_outcome_detail_data(study, outcomes_table, comments)
    outcomes = Outcome.find(:all, :order => "id",
                            :conditions => { study_id: study.id, extraction_form_id: 194 })
    outcome_details = OutcomeDetail.find(:all, :order => "id",
                                         :conditions => { extraction_form_id: 194,
                                                          is_matrix: 0 })
    outcomes.each_with_index do |outcome, n|
        outcome_details.each_with_index do |outcome_detail, m|
            _value = trans_yes_no_nd(outcomes_table[n+1][m+2])
            if outcome_detail[:question] == "Comments"
                _value = comments[1][2]
            end
            OutcomeDetailDataPoint.create(
                outcome_detail_field_id: outcome_detail.id,
                value: _value,#trans_yes_no_nd(outcomes_table[n+1][m+2]),
                notes: nil,
                study_id: study.id,
                extraction_form_id: 194,
                subquestion_value: nil,
                row_field_id: 0,
                column_field_id: 0,
                arm_id: 0,
                outcome_id: outcome.id
            )
        end
    end
end

def insert_confounders_info(study, confounders)
    confounders_row1 = confounders[1]
    confounders[1] = confounders_row1[2..-1]
    outcomes = Outcome.find(:all, :order => "id", :conditions => { study_id: study.id, extraction_form_id: 194 })
    outcome_details = OutcomeDetail.find(:all, :order => "question_number",
                                         :conditions => { extraction_form_id: 194,
                                                          is_matrix: 1 })
    outcomes.each do |outcome|
        outcome_details.each do |outcome_detail|
            outcome_detail_field_rows    = OutcomeDetailField.find(:all, :order => "row_number",
                                                                   :conditions => { outcome_detail_id: outcome_detail.id,
                                                                                    column_number: 0 })
            outcome_detail_field_columns = OutcomeDetailField.find(:all, :order => "column_number",
                                                                   :conditions => { outcome_detail_id: outcome_detail.id,
                                                                                    row_number: 0 })

            outcome_detail_field_rows.each_with_index do |outcome_detail_field_row, m|
                outcome_detail_field_columns.each_with_index do |outcome_detail_field_column, n|
                    OutcomeDetailDataPoint.create(
                        outcome_detail_field_id: outcome_detail.id,
                        value: trans_yes_no_nd(confounders[m+1][n+1]),
                        notes: nil,
                        study_id: study.id,
                        extraction_form_id: 194,
                        subquestion_value: nil,
                        row_field_id: outcome_detail_field_row.id,
                        column_field_id: outcome_detail_field_column.id,
                        arm_id: 0,
                        outcome_id: outcome.id
                    )
                end
            end
        end
    end
end

def build_results(study, doc)
    main_more_than_two_continuous, main_exactly_two_continuous, main_more_than_two_dichotomous, main_exactly_two_dichotomous,
        sub_more_than_two_continuous, sub_exactly_two_continuous, sub_more_than_two_dichotomous, sub_exactly_two_dichotomous = split_results_tables_into_groups(doc)

    #main_more_than_two_continuous.each do |table|
    #    table.each do |row|
    #        p row
    #    end
    #end

    main_exactly_two_continuous.each do |table|
        table = table[1..-1]
        table.each_with_index do |row, i|
            h_unit = row[3] unless row[7].blank?
            if i.even?
                h_exposure = row[4]
                h_mean = row[5]
                h_analyzed = row[6]
                h_baseline = row[7]
                h_baseline_ci = row[8]
                h_final = row[9]
                h_final_sd = row[10]
                h_net_difference = row[11]
                h_net_difference_CI = row[12]
                h_p_between = row[13]
            else
                h_exposure = row[0]
                h_mean = row[1]
                h_analyzed = row[2]
                h_baseline = row[3]
                h_baseline_ci = row[4]
                h_final = row[5]
                h_final_sd = row[6]
            end
            if i.even?
                unless row[4].blank?
                    arm = Arm.find(:first, :conditions => 
                                  ["study_id=? AND title LIKE ? AND extraction_form_id=194", "#{study.id}", "%#{h_exposure}%"])
                    p arm
                    if arm.blank?
                        arm = Arm.create(
                            study_id: study.id,
                            title: h_exposure,
                            description: "",
                            display_number: Arm.find(:all, :conditions => { study_id: study.id,
                                                                            extraction_form_id: 194 }),
                            extraction_form_id: 194,
                            is_suggested_by_admin: 0,
                            note: nil,
                            efarm_id: nil,
                            default_num_enrolled: nil,
                            is_intention_to_treat: 1
                        )
                    end
                    o = Outcome.create(
                        study_id: study.id,
                        title: row[2],
                        is_primary: 1,
                        units: h_unit,
                        description: "",
                        notes: "",
                        outcome_type: "Continuous",
                        extraction_form_id: 194
                    )
                    t = OutcomeTimepoint.create(
                        outcome_id: o.id,
                        number: "N/A",
                        time_unit: "N/A"
                    )
                    s = OutcomeSubgroup.create(
                        outcome_id: o.id,
                        title: "All Participants",
                        description: "All participants involved in the study (Default)"
                    )
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: o.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: o.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: s.id}).length + 1,
                        subgroup_id: s.id
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Follow-up, mo',
                        description: '',
                        unit: '',
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_mean),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. Analyzed',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_analyzed),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Baseline',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_baseline),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Baseline CI / SE / SD*',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_baseline_ci),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Final or Delta**',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_final),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Final or Delta CI / SE / SD*',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_final_sd),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    comparison = Comparison.create(
                        within_or_between: 'between',
                        study_id: study.id,
                        extraction_form_id: 194,
                        outcome_id: o.id,
                        group_id: t.id,
                        subgroup_id: s.id,
                        section: 0
                    )
                    comparison_measure_net_difference = ComparisonMeasure.create(
                        title: 'Net difference',
                        description: '',
                        unit: '',
                        note: '',
                        comparison_id: comparison.id,
                        measure_type: 1
                    )
                    comparison_measure_net_difference_ci = ComparisonMeasure.create(
                        title: 'Net difference CI / SE / SD*',
                        description: '',
                        unit: '',
                        note: '',
                        comparison_id: comparison.id,
                        measure_type: 1
                    )
                    comparison_measure_p_between = ComparisonMeasure.create(
                        title: 'P between',
                        description: '',
                        unit: '',
                        note: '',
                        comparison_id: comparison.id,
                        measure_type: 1
                    )
                    comparator = Comparator.create(
                        comparison_id: comparison.id,
                        comparator: "#{arm.id}_#{arm.id + 1}",
                    )
                    ComparisonDataPoint.create(
                        value: h_net_difference,
                        footnote: nil,
                        is_calculated: nil,
                        comparison_measure_id: comparison_measure_net_difference.id,
                        comparator_id: comparator.id,
                        arm_id: 0,
                        footnote_number: 0,
                        table_cell: nil
                    )
                    ComparisonDataPoint.create(
                        value: h_net_difference_CI,
                        footnote: nil,
                        is_calculated: nil,
                        comparison_measure_id: comparison_measure_net_difference_ci.id,
                        comparator_id: comparator.id,
                        arm_id: 0,
                        footnote_number: 0,
                        table_cell: nil
                    )
                    ComparisonDataPoint.create(
                        value: h_p_between,
                        footnote: nil,
                        is_calculated: nil,
                        comparison_measure_id: comparison_measure_p_between.id,
                        comparator_id: comparator.id,
                        arm_id: 0,
                        footnote_number: 0,
                        table_cell: nil
                    )
                end
            else
                unless row[0].blank?
                    arm = Arm.find(:first, :conditions => 
                                  ["study_id=? AND title LIKE ? AND extraction_form_id=194", "#{study.id}", "%#{row[0]}%"])
                    p arm
                    if arm.blank?
                        Arm.create(
                            study_id: study.id,
                            title: row[0],
                            description: "",
                            display_number: Arm.find(:all, :conditions => { study_id: study.id,
                                                                            extraction_form_id: 194 }),
                            extraction_form_id: 194,
                            is_suggested_by_admin: 0,
                            note: nil,
                            efarm_id: nil,
                            default_num_enrolled: nil,
                            is_intention_to_treat: 1
                        )
                    end
                    o = Outcome.create(
                        study_id: study.id,
                        title: row[0],
                        is_primary: 1,
                        units: h_unit,
                        description: "",
                        notes: "",
                        outcome_type: "Continuous",
                        extraction_form_id: 194
                    )
                    t = OutcomeTimepoint.create(
                        outcome_id: o.id,
                        number: "N/A",
                        time_unit: "N/A"
                    )
                    s = OutcomeSubgroup.create(
                        outcome_id: o.id,
                        title: "All Participants",
                        description: "All participants involved in the study (Default)"
                    )
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: o.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: o.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: s.id}).length + 1,
                        subgroup_id: s.id
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Follow-up, mo',
                        description: '',
                        unit: '',
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_mean),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. Analyzed',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_analyzed),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Baseline',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_baseline),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Baseline CI / SE / SD*',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_baseline_ci),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Final or Delta**',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_final),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Final or Delta CI / SE / SD*',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_final_sd),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                end
            end
        end
    end


    main_more_than_two_dichotomous.each do |table|
        table = table[1..-1]
        unless table[0][0].blank?
            table.each do |row|
                p row
                arm = Arm.find(:first, :conditions =>
                               ["study_id=? AND title LIKE ? AND extraction_form_id=194", "#{study.id}", "%#{row[3]}%"])
                if arm.blank?
                    arm = Arm.create(
                        study_id: study.id,
                        title: row[3],
                        description: "",
                        display_number: Arm.find(:all, :conditions => { study_id: study.id,
                                                                        extraction_form_id: 194 }),
                        extraction_form_id: 194,
                        is_suggested_by_admin: 0,
                        note: nil,
                        efarm_id: nil,
                        default_num_enrolled: nil,
                        is_intention_to_treat: 1
                    )
                end
                unless row[2].blank?
                    o = Outcome.create(
                        study_id: study.id,
                        title: row[2],
                        is_primary: 1,
                        units: "",
                        description: row[3],
                        notes: "",
                        outcome_type: "Categorical",
                        extraction_form_id: 194
                    )
                    t = OutcomeTimepoint.create(
                        outcome_id: o.id,
                        number: "N/A",
                        time_unit: "N/A"
                    )
                    s = OutcomeSubgroup.create(
                        outcome_id: o.id,
                        title: "All Participants",
                        description: "All participants involved in the study (Default)"
                    )
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: o.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: o.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: s.id}).length + 1,
                        subgroup_id: s.id
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Vit D level/dose',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[4]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Ca level/dose',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[5]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. of Cases',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[6]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. of Non-cases',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[7]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Crude or Adjusted analysis?',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[8]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Outcome Metric (e.g. OR, RR, HR, %)',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[9]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Outcome effect size',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[10]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'CI',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[11]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'P for trend***',
                        description: 'Enter a Description Here',
                        unit:  nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[13]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                else
                    o = Outcome.find(:last, :conditions => {
                        study_id: study.id,
                        outcome_type: "Categorical",
                        extraction_form_id: 194
                    })
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: o.id,
                        number: "N/A",
                        time_unit: "N/A"
                    })
                    s = OutcomeSubgroup.find(:last, :conditions => {
                        outcome_id: o.id,
                        title: "All Participants",
                        description: "All participants involved in the study (Default)"
                    })
                    outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                        outcome_id: o.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        subgroup_id: s.id
                    })
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Vit D level/dose',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Mean Vit D level/dose',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[4]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Ca level/dose',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Mean Ca level/dose',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[5]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. of Cases',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'No. of Cases',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[6]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. of Non-cases',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'No. of Non-cases',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[7]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Crude or Adjusted analysis?',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Crude or Adjusted analysis?',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[8]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Outcome Metric (e.g. OR, RR, HR, %)',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Outcome Metric (e.g. OR, RR, HR, %)',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[9]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Outcome effect size',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Outcome effect size',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[10]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'CI',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'CI',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[11]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'P for trend***',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'CI',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[13]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                end
            end
        end
    end

    #main_exactly_two_dichotomous.each do |table|
    #    table.each do |row|
    #        p row
    #    end
    #end

    #sub_more_than_two_continuous.each do |table|
    #    table.each do |row|
    #        p row
    #    end
    #end

    #sub_exactly_two_continuous.each do |table|
    #    table.each do |row|
    #        p row
    #    end
    #end

    sub_more_than_two_dichotomous.each do |table|
        table = table[1..-1]
        unless table.blank?
            table.each do |row|
                p row
                arm = Arm.find(:first, :conditions =>
                               ["study_id=? AND title LIKE ? AND extraction_form_id=194", "#{study.id}", "%#{row[3]}%"])
                if arm.blank?
                    arm = Arm.create(
                        study_id: study.id,
                        title: row[3],
                        description: "",
                        display_number: Arm.find(:all, :conditions => { study_id: study.id,
                                                                        extraction_form_id: 194 }),
                        extraction_form_id: 194,
                        is_suggested_by_admin: 0,
                        note: nil,
                        efarm_id: nil,
                        default_num_enrolled: nil,
                        is_intention_to_treat: 1
                    )
                end
                unless row[2].blank?
                    _outcomes = Outcome.find(:all, :conditions => {
                        study_id: study.id,
                        extraction_form_id: 194
                    })
                    _outcomes.each do |out|
                        if row[2].downcase.contains?(out.title)
                            o = Outcome.find(:first, :conditions => {
                                study_id: study.id,
                                title: out.title,
                                is_primary: 1,
                                outcome_type: "Categorical",
                                extraction_form_id: 194
                            })
                            s = OutcomeSubgroup.create(
                                outcome_id: o.id,
                                title: row[2],
                                description: "All participants involved in the study (Default)"
                            )
                            break
                        end
                    end
                    if o.blank?
                        o = Outcome.create(
                            study_id: study.id,
                            title: row[2],
                            is_primary: 1,
                            units: "",
                            description: row[3],
                            notes: "",
                            outcome_type: "Categorical",
                            extraction_form_id: 194
                        )
                        s = OutcomeSubgroup.create(
                            outcome_id: o.id,
                            title: row[2],
                            description: "All participants involved in the study (Default)"
                        )
                    end
                    t = OutcomeTimepoint.find(:first, :conditions => {
                        outcome_id: o.id,
                        number: "N/A",
                        time_unit: "N/A"
                    })
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: o.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: o.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: s.id}).length + 1,
                        subgroup_id: s.id
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Vit D level/dose',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[4]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Ca level/dose',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[5]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. of Cases',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[6]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. of Non-cases',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[7]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Crude or Adjusted analysis?',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[8]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Outcome Metric (e.g. OR, RR, HR, %)',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[9]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Outcome effect size',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[10]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.create(
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'CI',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    )
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[11]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                else
                    o = Outcome.find(:last, :conditions => {
                        study_id: study.id,
                        outcome_type: "Categorical",
                        extraction_form_id: 194
                    })
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: o.id,
                        number: "N/A",
                        time_unit: "N/A"
                    })
                    s = OutcomeSubgroup.find(:last, :conditions => {
                        outcome_id: o.id,
                        title: "All Participants",
                        description: "All participants involved in the study (Default)"
                    })
                    outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                        outcome_id: o.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        subgroup_id: s.id
                    })
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Vit D level/dose',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Mean Vit D level/dose',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[4]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Ca level/dose',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Mean Ca level/dose',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[5]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. of Cases',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'No. of Cases',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[6]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. of Non-cases',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'No. of Non-cases',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[7]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Crude or Adjusted analysis?',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Crude or Adjusted analysis?',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[8]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Outcome Metric (e.g. OR, RR, HR, %)',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Outcome Metric (e.g. OR, RR, HR, %)',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[9]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Outcome effect size',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'Outcome effect size',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[10]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'CI',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'CI',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[11]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'P for trend***',
                    })
                    #om = OutcomeMeasure.create(
                    #    outcome_data_entry_id: outcome_data_entry.id,
                    #    title: 'CI',
                    #    description: 'Enter a Description Here',
                    #    unit: nil,
                    #    note: nil,
                    #    measure_type: 0
                    #)
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[13]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                end
            end
        end
    end

    #sub_exactly_two_dichotomous.each do |table|
    #    table.each do |row|
    #        p row
    #    end
    #end

    #[main_more_than_two_continuous, main_exactly_two_continuous, main_more_than_two_dichotomous, main_exactly_two_dichotomous,
    #    sub_more_than_two_continuous, sub_exactly_two_continuous, sub_more_than_two_dichotomous, sub_exactly_two_dichotomous].each do |type|
    #    type.each do |table|
    #        table.each do |row|
    #            p row
    #        end
    #    end
    #    p "===================================================================================================="
    #    p "===================================================================================================="
    #    gets
    #end
end

## Splits up all the different kinds of result tables
## NOKOGIRI -> [[[ARRAY][ARRAY]..[ARRAY]]]
def split_results_tables_into_groups(doc)
    main_exactly_two_continuous = Array.new
    main_exactly_two_dichotomous = Array.new
    main_more_than_two_continuous = Array.new
    main_more_than_two_dichotomous = Array.new
    sub_exactly_two_continuous = Array.new
    sub_exactly_two_dichotomous = Array.new
    sub_more_than_two_continuous = Array.new
    sub_more_than_two_dichotomous = Array.new

    temp_main_cont = Array.new
    temp_main_dich = Array.new
    temp_sub_cont = Array.new
    temp_sub_dich = Array.new

    border = doc.xpath("//*[text()[contains(., '-----Subgroup\nAnalyses')]]")

    cont_top = border.xpath("./preceding::*[contains(text(), 'CONTINOUS')]")
    cont_top.each do |ct_noko|
        temp = ct_noko.xpath("./following::table[1]")
        temp = split_table_data(temp)
        temp_main_cont << temp
    end

    dich_top = border.xpath("./preceding::*[contains(text(), 'DICHOTOMOUS')]")
    dich_top.each do |dt_noko|
        temp = dt_noko.xpath("./following::table[1]")
        temp = split_table_data(temp)
        temp_main_dich << temp
    end

    cont_bottom = border.xpath("./following::*[contains(text(), 'CONTINOUS')]")
    cont_bottom.each do |cb_noko|
        temp = cb_noko.xpath("./following::table[1]")
        temp = split_table_data(temp)
        temp_sub_cont << temp
    end

    dich_bottom = border.xpath("./following::*[contains(text(), 'DICHOTOMOUS')]")
    dich_bottom.each do |db_noko|
        temp = db_noko.xpath("./following::table[1]")
        temp = split_table_data(temp)
        temp_sub_dich << temp
    end

    temp_main_cont.each do |t|
        if t[0][5].downcase.include?('crude')
            main_more_than_two_continuous << t
        else
            main_exactly_two_continuous << t
        end
    end

    temp_main_dich.each do |t|
        if t[0][3].downcase.include?('tirtiles') or t[0][3].downcase.include?('tertiles')
            main_more_than_two_dichotomous << t
        else
            main_exactly_two_dichotomous << t
        end
    end

    temp_sub_cont.each do |t|
        if t[0][5].downcase.include?('crude')
            sub_more_than_two_continuous << t
        else
            sub_exactly_two_continuous << t
        end
    end

    temp_sub_dich.each do |t|
        if t[0][3].downcase.include?('tirtiles')
            sub_more_than_two_dichotomous << t
        else
            sub_exactly_two_dichotomous << t
        end
    end

    return main_more_than_two_continuous, main_exactly_two_continuous, main_more_than_two_dichotomous, main_exactly_two_dichotomous,
        sub_more_than_two_continuous, sub_exactly_two_continuous, sub_more_than_two_dichotomous, sub_exactly_two_dichotomous
end

def build_other_results(study, doc)
end

def insert_adverse_events
end

def build_mean_data(study, mean)
end

def create_single_arm_for_all_participants(study)
    Arm.create(
        study_id: study.id,
        title: "All Participants",
        description: "",
        display_number: 1,
        extraction_form_id: 194,
        is_suggested_by_admin: 0,
        is_intention_to_treat: 1
    )
end



if __FILE__ == $0
    key_question_id_list = [356, 357, 358, 359, 360]
    table_array = Array.new
    pmids = Array.new

    validate_arg_list(opts)

    ## Load rails environment so we can access database object as well as use rails
    ## specific methods like blank?
    load_rails_environment

    doc = parse_html_file(opts)
    table_array = get_table_data(doc)

    eligibility                  = table_array[0]  # ELIGIBILITY CRITERIA AND OTHER CHARACTERISTICS
    population                   = table_array[1]  # POPULATION (BASELINE)
    background                   = table_array[2]  # Background Diet
    intervention                 = table_array[3]  # INTERVENTION(S), SKIP IF OBSERVATIONAL STUDY
    outcomes                     = table_array[4]  # LIST OF ALL OUTCOMES
    #two_dichotomous              = table_array[5]  # 2 ARMS/GROUPS: DICHOTOMOUS OUTCOMES
    #two_continuous               = table_array[6]  # 2 ARMS/GROUPS: CONTINUOUS OUTCOMES
    #more_than_two_dichotomous    = table_array[7]  # ≥2 ARMS/GROUPS: DICHOTOMOUS OUTCOMES
    #more_than_two_continuous     = table_array[8]  # ≥2 ARMS/GROUPS: CONTINUOUS OUTCOMES
    mean                         = table_array[5]  # MEAN DATA
    other_results                = table_array[6]  # OTHER RESULTS
    quality_interventional       = table_array[7]  # QUALITY of INTERVENTIONAL STUDIES
    quality_case_control_studies = table_array[8]  # QUALITY of COHORT OR NESTED CASE-CONTROL STUDIES
    comments                     = table_array[9]  # Comments
    comments_results             = table_array[10]  # Comments for Results
    confounders                  = table_array[11]  # Confounders

    #p eligibility
    #p population
    #p background
    #p intervention
    #p outcomes
    #p comments
    #p confounders
    #p two_dichotomous
    #p two_continuous
    #p more_than_two_dichotomous
    #p more_than_two_continuous
    #p mean
    #p other_results
    #p comments_results
    #p quality_interventional
    #p quality_case_control_studies

    ## Each study for this project has the pubmed ID recorded in almost every table under the
    ## `UI' heading. For the sake of simplicity and consistency we will retrieve the pmid from the
    ## `ELIGIBILITY CRITERIA AND OTHER CHARACTERISTICS' table
    pmid = retrieve_pmid_from_eligibility_table(eligibility)
    if pmid.blank?
        puts "*** ERROR ***"
        puts "No UI value found"
        gets
    else
        ## Study.create_for_pmids expects pmids to be an array, so we wrap pmid
        pmids << pmid
    end

    ## Insert Publication data
    kq_hash = {kq: 355}
    Study.create_for_pmids(pmids, key_questions=kq_hash, project_id=135, extraction_form_id=193, user_id=1)

    ## Find the study that was created by Study.create_for_pmids
    study_id = PrimaryPublication.last(conditions: { pmid: pmid }).study_id
    study = Study.find_by_id(study_id)

    ## Check if this study has QUALITY of INTERVENTIONAL STUDIES
    ## key_question_id: 361
    if quality_of_interventional_studies?(quality_interventional)
        ##puts "QUALITY of INTERVENTIONAL STUDIES found"
        add_study_to_key_questions_association_qoi(study)
        add_quality_dimension_data_points_qoi(quality_interventional, study)
        key_question_id_list << 361
    end

    ## key_question_id: 362
    if quality_of_cohort_or_nested_case_control_studies?(quality_case_control_studies)
        #puts "QUALITY of COHORT OR NESTED CASE-CONTROL STUDIES found"
        add_study_to_key_questions_association_qoc(study)
        add_quality_dimension_data_points_qoc(quality_case_control_studies, study)
        key_question_id_list << 362

        ## Since this is an observational study, there are no arms created.
        ## However, we need at least one for results table
        create_single_arm_for_all_participants(study)
    end

    add_study_to_key_questions_association(key_question_id_list, study)

    ## This is taken care of by Study.create_for_pmids
    #add_study_to_extraction_form_association(study)

    insert_design_detail_data(study, eligibility, background)

    ## Create arms if intervention table is not empty
    unless interventions?(intervention)
        create_arms(study, intervention)
    end
    insert_arm_detail_data(study, intervention)

    insert_baseline_characteristics(study, population)

    ## Changed my mind about this one. We will create outcomes when we scan the results tables
    #create_outcomes(study, outcomes)

    insert_outcome_detail_data(study, outcomes, comments)
    insert_confounders_info(study, confounders)

    ### Todo !!!
    build_results(study, doc)
    build_mean_data(study, mean)
    build_other_results(study, doc)
    #insert_adverse_events ???
end
