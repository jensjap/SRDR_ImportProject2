require 'nokogiri'
require_relative "trollop"

# This program reads in an html document and extract data to be
# inserted into a SRDR project
#
# Author::    Jens Jap  (mailto:jens_jap@brown.edu)
# Copyright::
# License::   Distributes under the same terms as Ruby

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
# nil -> Nokogiri
def retrieve_tables(opts)
    f = File.open(opts[:file])
    doc = Nokogiri::HTML(f)
    doc.xpath('/html/body/table')
end

# Find table row elements out of Nokogiri type object and packages them up
# into an array
# Nokogiri -> Array
def get_table_data(table)
    temp = Array.new
    rows = table.xpath('./tr')
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

def create_outcomes
end

def insert_outcome_detail_data
end

def build_results
end

def insert_adverse_events
end



if __FILE__ == $0
    key_question_id_list = [356, 357, 358, 359, 360]
    table_array = Array.new
    pmids = Array.new

    validate_arg_list(opts)

    tables = retrieve_tables(opts)
    tables.each do |table|
        table_data = get_table_data(table)
        table_array << table_data
    end

    eligibility                  = table_array[0]  # ELIGIBILITY CRITERIA AND OTHER CHARACTERISTICS
    population                   = table_array[1]  # POPULATION (BASELINE)
    background                   = table_array[2]  # Background Diet
    intervention                 = table_array[3]  # INTERVENTION(S), SKIP IF OBSERVATIONAL STUDY
    outcomes                     = table_array[4]  # LIST OF ALL OUTCOMES
    comments                     = table_array[5]  # Comments
    confounders                  = table_array[6]  # Confounders
    two_dichotomous              = table_array[7]  # 2 ARMS/GROUPS: DICHOTOMOUS OUTCOMES
    two_continuous               = table_array[8]  # 2 ARMS/GROUPS: CONTINUOUS OUTCOMES
    more_than_two_dichotomous    = table_array[9]  # ≥2 ARMS/GROUPS: DICHOTOMOUS OUTCOMES
    more_than_two_continuous     = table_array[10]  # ≥2 ARMS/GROUPS: CONTINUOUS OUTCOMES
    mean                         = table_array[11]  # MEAN DATA
    other_results                = table_array[12]  # OTHER RESULTS
    comments_results             = table_array[13]  # Comments for Results
    quality_interventional       = table_array[14]  # QUALITY of INTERVENTIONAL STUDIES
    quality_case_control_studies = table_array[15]  # QUALITY of COHORT OR NESTED CASE-CONTROL STUDIES

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

    # Load rails environment so we can access database object as well as use rails
    # specific methods like blank?
    load_rails_environment

    # Each study for this project has the pubmed ID recorded in almost every table under the
    # `UI' heading. For the sake of simplicity and consistency we will retrieve the pmid from the
    # `ELIGIBILITY CRITERIA AND OTHER CHARACTERISTICS' table
    pmid = retrieve_pmid_from_eligibility_table(eligibility)
    if pmid.blank?
        puts "*** ERROR ***"
        puts "No UI value found"
        gets
    else
        # Study.create_for_pmids expects pmids to be an array, so we wrap pmid
        pmids << pmid
    end

    # Insert Publication data
    kq_hash = {kq: 355}
    Study.create_for_pmids(pmids, key_questions=kq_hash, project_id=135, extraction_form_id=193, user_id=1)

    # Find the study that was created by Study.create_for_pmids
    study_id = PrimaryPublication.last(conditions: { pmid: pmid }).study_id
    study = Study.find_by_id(study_id)

    # Check if this study has QUALITY of INTERVENTIONAL STUDIES
    # key_question_id: 361
    if quality_of_interventional_studies?(quality_interventional)
        #puts "QUALITY of INTERVENTIONAL STUDIES found"
        add_study_to_key_questions_association_qoi(study)
        add_quality_dimension_data_points_qoi(quality_interventional, study)
        key_question_id_list << 361
    #else
        #puts "No QUALITY of INTERVENTIONAL STUDIES found"
    end

    # key_question_id: 362
    if quality_of_cohort_or_nested_case_control_studies?(quality_case_control_studies)
        #puts "QUALITY of COHORT OR NESTED CASE-CONTROL STUDIES found"
        add_study_to_key_questions_association_qoc(study)
        add_quality_dimension_data_points_qoc(quality_case_control_studies, study)
        key_question_id_list << 362
    #else
        #puts "No QUALITY of COHORT OR NESTED CASE-CONTROL STUDIES found"
    end

    add_study_to_key_questions_association(key_question_id_list, study)

    # This is taken care of by Study.create_for_pmids
    #add_study_to_extraction_form_association(study)

    insert_design_detail_data(study, eligibility, background)

    # Create arms if intervention table is not empty
    unless interventions?(intervention)
        create_arms(study, intervention)
        insert_arm_detail_data(study, intervention)
    end

    ## Todo !!!
    create_outcomes
    insert_outcome_detail_data
    build_results
    #insert_adverse_events
end
