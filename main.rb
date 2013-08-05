## encoding: UTF-8

require 'nokogiri'
require_relative "trollop"

## This program reads in an html document and extract data to be
## inserted into a SRDR project
##
## Author::    Jens Jap  (mailto:jens_jap@brown.edu)
## Copyright::
## License::   Distributes under the same terms as Ruby

@errors = Array.new

## Loads the rails environment so we have access to the models {{{1
def load_rails_environment
    ENV["RAILS_ENV"] = ENV["RAILS_ENV"] || "development"
    require File.expand_path(File.dirname(__FILE__) + "./../SRDR/config/environment")
end

## Minimal arg parser {{{1
## http://trollop.rubyforge.org/
opts = Trollop::options do
    opt :file,            "Filename",              :type => :string,  :default => ARGV[0]
    opt :project_id,      "Project ID",            :type => :integer, :default => 135
    opt :creator_id,      "Creator ID",            :type => :integer, :default => 1
    opt :dry_run,         "Dry-run. No database modifications take place"
    opt :analyze,         "Run the crawler and display statistical summary"
end

## Ensures that required arguments have been received {{{1
## Options hash -> Boolean
def validate_arg_list(opts)
    Trollop::die :file,            "Missing file name"                 unless opts[:file_given]
end

## Strips the text from any new line and tabs {{{1
## String -> String
def clean_text(s)
    s.strip.gsub(/\n\t/, " ").gsub(/\t/, "").gsub("  ", " ")
end

## Looks for `table' tags in the document and retrieves them {{{1
## using nokogiri parser
## file -> Nokogiri
#def parse_html_file(opts)
def parse_html_file(file)
    f = File.open(file)
    Nokogiri::HTML(f)
end

## Sorts a nokogiri document into tables and appends them to an array {{{1
def get_table_data(doc)
    tables = Array.new

    ## ELIGIBILITY CRITERIA AND OTHER CHARACTERISTICS
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

    ## "MEAN\nDATA. THIS SHOULD ONLY APPLY TO CASE-COHORT STUDIES"
    table = doc.xpath("/html/body/p//*[contains(text(), 'MEAN\nDATA. THIS SHOULD ONLY APPLY TO CASE-COHORT STUDIES')]/ancestor::p[1]/following-sibling::table[1]")
    table = split_table_data(table)
    tables << table

    ## "OTHER RESULTS"
    table = doc.xpath("/html/body/p//*[contains(text(), 'OTHER\nRESULTS')]/ancestor::p[1]/following-sibling::table[1]")
    table = split_table_data(table)
    tables << table

    ## "QUALITY of INTERVENTIONAL STUDIES"
    table = doc.xpath("/html/body/p//*[contains(text(), 'QUALITY\nof INTERVENTIONAL STUDIES')]/ancestor::p[1]/following-sibling::table[1]")
    table = split_table_data(table)
    tables << table

    ## "QUALITY of COHORT OR NESTED CASE-CONTROL STUDIES"
    table = doc.xpath("/html/body/p//*[contains(text(), 'QUALITY\nof COHORT OR NESTED CASE-CONTROL STUDIES')]/ancestor::p[1]/following-sibling::table[1]")
    table = split_table_data(table)
    tables << table

    ## Comments
    table = doc.xpath('/html/body/table//td//*[contains(text(), "Comments")]')[0].xpath('./ancestor::table[1]')
    table = split_table_data(table)
    tables << table

    ## Comments for results
    table = doc.xpath('/html/body/table//td//*[contains(text(), "Comments")]')[1].xpath('./ancestor::table[1]')
    table = split_table_data(table)
    tables << table

    ## Confounders
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

## Find table row elements out of Nokogiri type object and packages them up {{{1
## into an array
## Nokogiri -> Array
def split_table_data(table)
    temp = Array.new
    rows = table.xpath('.//tr')
    rows.each do |row|
        temp << convert_to_array(row)
    end
    return temp
end

## Helper to get_table_data function. Does the same procedure but at the row {{{1
## level by cutting the row into the table data elements (columns) and packaging
## them up into an array
## Nokogiri -> Array
def convert_to_array(row_data)
    temp = Array.new
    rows = row_data.xpath('./td')
    rows.each do |row|
        temp << clean_text(row.text())
    end
    return temp
end

## Creates an entry in `studies' table {{{1
## Options Hash -> Study
def create_study(opts)
    Study.create(project_id: opts[:project_id],
                 creator_id: opts[:creator_id])
end

## Associates key questions to study by inserting into `study_key_questions' table {{{1
def add_study_to_key_questions_association(key_question_id_list, study)
    key_question_id_list.each do |n|
        StudyKeyQuestion.create(study_id: study.id,
                                key_question_id: n,
                                extraction_form_id: 194)
    end
end

## Associates key questions to study by inserting into `study_key_questions' table {{{1
## Only when Quality Of Interventional Studies exists
def add_study_to_key_questions_association_qoi(study)
    StudyKeyQuestion.create(study_id: study.id,
                            key_question_id: 361,
                            extraction_form_id: 190)
    StudyExtractionForm.create(study_id: study.id,
                               extraction_form_id: 190)
end

## Associates key questions to study by inserting into `study_key_questions' table {{{1
## Only when Quality Of Cohort Or Nested Case-Control Studies exists
def add_study_to_key_questions_association_qoc(study)
    StudyKeyQuestion.create(study_id: study.id,
                            key_question_id: 362,
                            extraction_form_id: 193)
    StudyExtractionForm.create(study_id: study.id,
                               extraction_form_id: 193)
end

## Associates study to extraction form by inserting into `study_extraction_forms' table {{{1
def add_study_to_extraction_form_association(study)
    StudyExtractionForm.create(study_id: study.id,
                               extraction_form_id: 194)
end

## Determines if quality of interventional studies table has any entries {{{1
## QualityOfInterventionalStudiesTableArray -> Boolean
def quality_of_interventional_studies?(q)
    ## First row are the headers. We need to look at the first element of the next row
    row = q[1]
    ## Return false if it is blank, else true
    row[0].blank? ? false : true
end

## Determines if quality of cohort or nested case control studies table has any entries {{{1
## QualityOfCohortOrNestedCaseControlStudiesTableArray -> Boolean
def quality_of_cohort_or_nested_case_control_studies?(q)
    ## First row are the headers. We need to look at the first element of the next row
    row = q[1]
    ## Return false if it is blank, else true
    row[0].blank? ? false : true
end

## Inserts publication information for this study {{{1
## Study EligibilityTableArray -> nil
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

## Uses the eligibility table to retrieve the UI value. The UI value corresponds to Pubmed IDs {{{1
## EligibilityTableArray -> Natural
def retrieve_pmid_from_eligibility_table(eligibility)
    ## Skip the header row
    first_data_row = eligibility[1]

    ## UI column
    first_data_row[0]
end

## Helper to translate short answers to full length {{{1
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

## Adds quality dimension data points for quality of interventional studies {{{1
def add_quality_dimension_data_points_qoi(quality_interventional, study)
    row = quality_interventional[1]
    adverse_event_value = quality_interventional[2][1]
    explanation = quality_interventional[3][1]
    fields = QualityDimensionField.find(:all, :order => "id", :conditions => { :extraction_form_id => 190 })
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[0].id,  ## appropriate randomization
        value: trans_yes_no_nd(row[3]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[1].id,  ## allocation concealment
        value: trans_yes_no_nd(row[4]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[2].id,  ## dropout rate < 20%
        value: trans_yes_no_nd(row[6]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[3].id,  ## blinded outcome
        value: trans_yes_no_nd(row[7]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[4].id,  ## intention to treat
        value: trans_yes_no_nd(row[8]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[5].id,  ## appropriate statistical analysis
        value: trans_yes_no_nd(row[9]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[6].id,  ## assessment for confounding
        value: trans_yes_no_nd(row[10]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[7].id,  ## clear reporting
        value: trans_yes_no_nd(row[11]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[8].id,  ## appropriate washout period
        value: trans_yes_no_nd(row[5]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[9].id,  ## design
        value: trans_yes_no_nd(row[2]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[10].id,  ## adverse events
        value: trans_yes_no_nd(adverse_event_value),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 190)
#    QualityDimensionDataPoint.create(
#        quality_dimension_field_id: fields[11].id,  ## overall grade
#        value: row[12],
#        notes: "",
#        study_id: study.id,
#        field_type: nil,
#        extraction_form_id: 190)
#    QualityDimensionDataPoint.create(
#        quality_dimension_field_id: fields[12].id,  ## explanation
#        value: explanation,
#        notes: "",
#        study_id: study.id,
#        field_type: nil,
#        extraction_form_id: 190)
    QualityRatingDataPoint.create(
        study_id: study.id,
        guideline_used: '',
        current_overall_rating: row[12],
        notes: explanation,
        extraction_form_id: 190,
    )
end

## Adds quality dimension data points for quality of cohort studies {{{1
def add_quality_dimension_data_points_qoc(quality_case_control_studies, study)
    overall_grade = quality_case_control_studies[4][1]
    explanation = quality_case_control_studies[5][1]
    row1 = quality_case_control_studies[1]
    row2 = quality_case_control_studies[2]
    row3 = quality_case_control_studies[3]
    fields = QualityDimensionField.find(:all, :order => "id", :conditions => { :extraction_form_id => 193 })
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[0].id,  ## eligibility criteria clear
        value: trans_yes_no_nd(row1[3]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[2].id,  ## exposure assessor blinded
        value: trans_yes_no_nd(row1[5]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[4].id,  ## method reported
        value: trans_yes_no_nd(row1[7]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[7].id,  ## one of the prespecified methods
        value: trans_yes_no_nd(row1[9]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[9].id,  ## level of the exposure
        value: trans_yes_no_nd(row1[11]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[10].id, ## adjusted or matched
        value: trans_yes_no_nd(row1[13]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[12].id,  ## clear definition
        value: trans_yes_no_nd(row1[15]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[15].id,  ## prospective collection
        value: trans_yes_no_nd(row1[17]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
#########################################
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[1].id,  ## sampling of population
        value: trans_yes_no_nd(row2[1]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[3].id,  ## outcome assessor
        value: trans_yes_no_nd(row2[3]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[5].id,  ## food composition database
        value: trans_yes_no_nd(row2[5]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[8].id,  ## time from sample
        value: trans_yes_no_nd(row2[7]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[13].id,  ## loss to follow up
        value: trans_yes_no_nd(row2[9]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[16].id,  ## analysis was planned
        value: trans_yes_no_nd(row2[11]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
#########################################
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[6].id,  ## internal calibration
        value: trans_yes_no_nd(row3[5]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[11].id,  ## justification
        value: trans_yes_no_nd(row3[11]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[14].id,  ## do the authors specify
        value: trans_yes_no_nd(row3[13]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
    QualityDimensionDataPoint.create(
        quality_dimension_field_id: fields[17].id,  ## justification of sample size
        value: trans_yes_no_nd(row3[15]),
        notes: "",
        study_id: study.id,
        field_type: nil,
        extraction_form_id: 193)
#########################################
#    QualityDimensionDataPoint.create(
#        quality_dimension_field_id: fields[18].id,  ## overall grade
#        value: overall_grade,
#        notes: "",
#        study_id: study.id,
#        field_type: nil,
#        extraction_form_id: 193)
#    QualityDimensionDataPoint.create(
#        quality_dimension_field_id: fields[19].id,  ## explanation
#        value: explanation,
#        notes: "",
#        study_id: study.id,
#        field_type: nil,
#        extraction_form_id: 193)
    QualityRatingDataPoint.create(
        study_id: study.id,
        guideline_used: '',
        current_overall_rating: overall_grade,
        notes: explanation,
        extraction_form_id: 193,
    )
end

## Inserts design detail data points into `design_detail_data_points' table {{{1
def insert_design_detail_data(study, eligibility, background)
    eligibility_data_row = eligibility[1]
    background_first_row = background[1]
    background_second_row = background[2]
    design_details_qs = DesignDetail.find(:all, :order => "question_number", :conditions => { extraction_form_id: 194 })
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[0].id,  ## study design
                                 value: trans_yes_no_nd(eligibility_data_row[2]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[1].id,  ## inclusion
                                 value: trans_yes_no_nd(eligibility_data_row[3]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[2].id,  ## exclusion
                                 value: trans_yes_no_nd(eligibility_data_row[4]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[3].id,  ## enrollment years
                                 value: trans_yes_no_nd(eligibility_data_row[5]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[4].id,  ## trial or cohort
                                 value: trans_yes_no_nd(eligibility_data_row[6]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    pp = PrimaryPublication.find_by_study_id(study.id)
    pp.trial_title = trans_yes_no_nd(eligibility_data_row[6])
    pp.save
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[5].id,  ## funding source
                                 value: trans_yes_no_nd(eligibility_data_row[7]),
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 0,
                                 column_field_id: 0,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: design_details_qs[6].id,  ## extractor
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
                                 value: trans_yes_no_nd(background_first_row[6]),  ## biomarker assay
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8678,
                                 column_field_id: 8683,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1927,
                                 value: trans_yes_no_nd(background_first_row[7]),  ## analytical validity
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8678,
                                 column_field_id: 8684,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1927,
                                 value: trans_yes_no_nd(background_first_row[8]),  ## time between
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8678,
                                 column_field_id: 8685,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1927,
                                 value: trans_yes_no_nd(background_first_row[9]),  ## season/date
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8678,
                                 column_field_id: 8686,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1927,
                                 value: trans_yes_no_nd(background_first_row[10]),  ## background exposure
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
    ## dietary calcium intake
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[3]),  ## dietary assessment method
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8663,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[4]),  ## food composition
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8664,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[5]),  ## internal calibration
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8665,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[6]),  ## biomarker assay
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8666,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[7]),  ## analytical validity
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8667,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[9]),  ## season/date
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8668,
                                 arm_id: 0,
                                 outcome_id: 0)
    DesignDetailDataPoint.create(design_detail_field_id: 1928,
                                 value: trans_yes_no_nd(background_second_row[10]),  ## background
                                 notes: nil,
                                 study_id: study.id,
                                 extraction_form_id: 194,
                                 subquestion_value: nil,
                                 row_field_id: 8662,
                                 column_field_id: 8669,
                                 arm_id: 0,
                                 outcome_id: 0)
end

## Test if 1st cell in intervention table is a number {{{1
## InterventionalTableArray -> Boolean
def interventions?(intervention)
    intervention[1][0].blank?
end

## Finds all arms for this study and attempts to make references to {{{1
## arms already created for this project. There are only 4 default
## to choose from atm; there might be more types of arms
## Study InterventionalTableArray -> nil
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

## Inserts arm detail data points {{{1
## Study InterventionalTableArray -> nil
## !!!
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

## Inserts baselineline characteristics. We are placing all values into All Arms (Total) {{{1
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

## Attempts to find all outcomes for this study and create an entry in `outcomes' table {{{1
def create_outcomes(study, outcomes)#, outcome_type)
    outcomes[1..-1].each_with_index do |row|
        unless row[3].blank?
            outcome = Outcome.create(
                study_id: study.id,
                title: row[3],
                is_primary: 1,
                units: "",
                description: row[4],
                notes: row[2],
                outcome_type: "",
                #outcome_type: outcome_type,
                extraction_form_id: 194
            )
            OutcomeTimepoint.create(
                outcome_id: outcome.id,
                number: "N/A",
                time_unit: "years"
            )
        end
    end
end

## Inserts outcome detail data points {{{1
def insert_outcome_detail_data(study, outcomes_table, comments)
    outcomes_table = outcomes_table[1..-1]
    #outcomes = Outcome.find(:all, :order => "id",
    #                        :conditions => { study_id: study.id, extraction_form_id: 194 })
    #outcomes.each_with_index do |outcome, n|
        outcomes_table.each_with_index do |row, m|
            unless row[0].blank?
                outcome = Outcome.find(:first, :order => "id",
                                       :conditions => { study_id: study.id,
                                                        extraction_form_id: 194,
                                                        title: row[3] })
                outcome_detail = OutcomeDetail.find(:first, :conditions => {
                    question: "Primary / Secondary Outcome",
                    extraction_form_id: 194
                })
                OutcomeDetailDataPoint.create(
                    outcome_detail_field_id: outcome_detail.id,
                    value: trans_yes_no_nd(row[2]),
                    notes: nil,
                    study_id: study.id,
                    extraction_form_id: 194,
                    subquestion_value: nil,
                    row_field_id: 0,
                    column_field_id: 0,
                    arm_id: 0,
                    outcome_id: outcome.id
                )
                outcome_detail = OutcomeDetail.find(:first, :conditions => {
                    question: "Outcome",
                    extraction_form_id: 194
                })
                OutcomeDetailDataPoint.create(
                    outcome_detail_field_id: outcome_detail.id,
                    value: trans_yes_no_nd(row[3]),
                    notes: nil,
                    study_id: study.id,
                    extraction_form_id: 194,
                    subquestion_value: nil,
                    row_field_id: 0,
                    column_field_id: 0,
                    arm_id: 0,
                    outcome_id: outcome.id
                )
                outcome_detail = OutcomeDetail.find(:first, :conditions => {
                    question: "Definition",
                    extraction_form_id: 194
                })
                OutcomeDetailDataPoint.create(
                    outcome_detail_field_id: outcome_detail.id,
                    value: trans_yes_no_nd(row[4]),
                    notes: nil,
                    study_id: study.id,
                    extraction_form_id: 194,
                    subquestion_value: nil,
                    row_field_id: 0,
                    column_field_id: 0,
                    arm_id: 0,
                    outcome_id: outcome.id
                )
                outcome_detail = OutcomeDetail.find(:first, :conditions => {
                    question: "Comments",
                    extraction_form_id: 194
                })
                OutcomeDetailDataPoint.create(
                    outcome_detail_field_id: outcome_detail.id,
                    value: trans_yes_no_nd(comments[1][2]),
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
    #end
end

## Inserts confounders data {{{1
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

## Given the outcome title, find it in the db or create a new one {{{1
## STRING STUDY -> OUTCOME
def create_outcome_if_needed(outcome_title, unit, study, outcome_type)
    outcome = Outcome.find(:last, :conditions =>
                           ["study_id=? AND title LIKE ? AND outcome_type=? AND extraction_form_id=?",
                            "#{study.id}", "%#{outcome_title}%", "Continuous", "194"])
    if outcome.blank?
        outcome = Outcome.create(
            study_id: study.id,
            title: outcome_title,
            is_primary: 1,
            units: unit,
            description: '',
            notes: '',
            outcome_type: outcome_type,
            extraction_form_id: 194,
        )
    end
    return outcome
end

## Creates arms but only if none with that name can be found for this study {{{1
def create_arm_if_needed(arm_title, study)
    arm = Arm.find(:last, :conditions =>
                   ["study_id=? AND title LIKE ? AND extraction_form_id=?",
                    "#{study.id}", "#{arm_title}%", "194"])
    if arm.blank?
        arm = Arm.create(
            study_id: study.id,
            title: arm_title,
            description: '',
            display_number: Arm.find(:all, :conditions => { study_id: study.id,
                                                            extraction_form_id: 194 }).length + 1,
            extraction_form_id: 194,
            is_suggested_by_admin: 0,
            is_intention_to_treat: 1
        )
    end
    return arm
end

## Finds the last outcome created, sorted by id {{{1
def find_last_outcome_created(study, outcome_type)
    Outcome.find(:last, :conditions => {
        study_id: study.id,
        outcome_type: outcome_type,
        extraction_form_id: 194
    })
end

## Attempts to find the outcome by study id, outcome title. Once found will modify the outcome to reflect appropriate {{{1
## unit and outcome_type. Then returns the outcome
## low := list of words
## best_choice = [OUTCOME, score]
## STUDY STRING STRING STRING -> OUTCOME
def search_for_outcome(study, title, unit, outcome_type, opts)
    score = 0
    best_choice = {best_outcome: Outcome.new, score: 0}
    outcome1_low = Array.new
    outcome2_low = Array.new

    outcome1_low = title.downcase.split(/[,\s]/).reject(&:empty?)
    outcomes = Outcome.find(:all, :conditions => {
        study_id: study.id,
        extraction_form_id: 194
    })
    outcomes.each do |outcome|
        if outcome.title.downcase == title.downcase
            best_outcome = outcome
            #p "Outcome chosen: #{best_outcome.title}"
            #p "By default because the title matched the outcome exactly"
            best_outcome.units = unit
            best_outcome.outcome_type = outcome_type
            best_outcome.save
            return best_outcome
        else
            outcome2_low = outcome.title.downcase.split(/[,\s]/).reject(&:empty?)
            outcome2_low.each do |o2|
                outcome1_low.each do |o1|
                    if o2 == o1
                        score = score + 1
                    end
                end
            end
            if score > best_choice[:score]
                best_choice = {best_outcome: outcome, score: score}
            end
        end
    end
    #p "Outcome chosen: #{best_choice[:best_outcome].title}"
    #p "With a score of: #{best_choice[:score]}"
    best_outcome = best_choice[:best_outcome]
    if best_outcome.id == nil
        best_outcome = Outcome.create(
            study_id: study.id,
            title: title,
            is_primary: 1,
            units: unit,
            description: "",
            notes: "",
            outcome_type: outcome_type,
            extraction_form_id: 194,
        )
        OutcomeTimepoint.create(
            outcome_id: best_outcome.id,
            number: "N/A",
            time_unit: "years"
        )
        File.open("matching_issues.txt",'a') do |filea|
           filea.puts "Problems matching outcomes for study #{opts[:file]}"
        end
    else
        best_outcome.outcome_type = outcome_type
        best_outcome.units = unit
        best_outcome.save
    end
    return best_outcome
end

## Looks for an outcome subgroup with the same outcome_id and title. If found, returns it. {{{1
## Else creates one and returns it
def search_for_outcome_subgroup(outcome_id, title)
#    outcome_sg = OutcomeSubgroup.find(:first, :conditions => {
#        outcome_id: outcome_id,
#        title: title
#    })
#    if outcome_sg.blank?
        outcome_sg = OutcomeSubgroup.create(
            outcome_id: outcome_id,
            title: title
        )
#    end
    return outcome_sg
end

## Builds the results table {{{1
def build_results(study, doc, opts)
    main_more_than_two_continuous, main_exactly_two_continuous, main_more_than_two_dichotomous, main_exactly_two_dichotomous,
        sub_more_than_two_continuous, sub_exactly_two_continuous, sub_more_than_two_dichotomous, sub_exactly_two_dichotomous = split_results_tables_into_groups(doc)

    main_more_than_two_continuous.each do |table|  #{{{2
        unless table[1][4].blank?
            table_headers = table[0]
            outcome_measures = table_headers[5..-4]
            table = table[1..-1]
            table.each do |row|
                unless row[2].blank?  # This is a row with a new outcome
                    @h_outcome_title = row[2]
                    @h_unit = row[3]
                    ##        create_outcome_if_needed(outcome_title, unit, study, outcome_type)
                    #outcome = create_outcome_if_needed(row[2], row[3], study, "Continuous")
                    #outcome = create_outcome_if_needed(row[2], row[3], study, "Continuous")
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Continuous", opts)
                    arm = create_arm_if_needed(arm_title=row[4], study)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #s = OutcomeSubgroup.create(
                    #    outcome_id: outcome.id,
                    #    title: row[4],
                    #    description: ""
                    #)
                    @s = search_for_outcome_subgroup(outcome.id, row[2])
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: outcome.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: @s.id}).length + 1,
                        subgroup_id: @s.id
                    )
                    outcome_measures.each_with_index do |measure, i|
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: measure,
                            description: '',
                            unit: '',
                            note: nil,
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(row[i + 5]),
                            footnote: nil,
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                    end
                else
                    ##        find_last_outcome_created(study, outcome_type)
                    #outcome = find_last_outcome_created(study, "Continuous")
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Continuous", opts)
                    arm = create_arm_if_needed(arm_title=row[4], study)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #s = OutcomeSubgroup.find(:last, :conditions => {
                    #    outcome_id: outcome.id,
                    #})
                    outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        subgroup_id: @s.id
                    })
                    outcome_measures.each_with_index do |measure, i|
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: measure,
                            description: '',
                            unit: '',
                            note: nil,
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(row[i + 5]),
                            footnote: nil,
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                    end
                end
            end
        end
    end

    main_exactly_two_continuous.each do |table|  #{{{2
        table = table[1..-1]
        table.each_with_index do |row, i|
            if i.even?
                @h_outcome_title = row[2]
                @h_unit = row[3]
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
                    if arm.blank?
                        arm = Arm.create(
                            study_id: study.id,
                            title: h_exposure,
                            description: "",
                            display_number: Arm.find(:all, :conditions => { study_id: study.id,
                                                                            extraction_form_id: 194 }).length + 1,
                            extraction_form_id: 194,
                            is_suggested_by_admin: 0,
                            note: nil,
                            efarm_id: nil,
                            default_num_enrolled: nil,
                            is_intention_to_treat: 1
                        )
                    end
#                    outcome = Outcome.create(
#                        study_id: study.id,
#                        title: row[2],
#                        is_primary: 1,
#                        units: @h_unit,
#                        description: "",
#                        notes: "",
#                        outcome_type: "Continuous",
#                        extraction_form_id: 194
#                    )
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Continuous", opts)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #@s = OutcomeSubgroup.create(
                    #    outcome_id: outcome.id,
                    #    title: "All Participants",
                    #    description: "All participants involved in the study (Default)"
                    #)
                    @s = search_for_outcome_subgroup(outcome.id, @h_outcome_title)
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: outcome.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: @s.id}).length + 1,
                        subgroup_id: @s.id
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
                        outcome_id: outcome.id,
                        group_id: t.id,
                        subgroup_id: @s.id,
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
                    if arm.blank?
                        arm = Arm.create(
                            study_id: study.id,
                            title: row[0],
                            description: "",
                            display_number: Arm.find(:all, :conditions => { study_id: study.id,
                                                                            extraction_form_id: 194 }).length + 1,
                            extraction_form_id: 194,
                            is_suggested_by_admin: 0,
                            note: nil,
                            efarm_id: nil,
                            default_num_enrolled: nil,
                            is_intention_to_treat: 1
                        )
                    end
#                    outcome = Outcome.find(:last, :conditions => {
#                        study_id: study.id,
#                        outcome_type: "Continuous",
#                        extraction_form_id: 194
#                    })
                    p "about to search for outcome with title: #{@h_outcome_title}, unit: #{@h_unit}"
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Continuous", opts)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #s = OutcomeSubgroup.find(:last, :conditions => {
                    #    outcome_id: outcome.id,
                    #    title: "All Participants",
                    #    description: "All participants involved in the study (Default)"
                    #})
                    outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        subgroup_id: @s.id
                    })
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Follow-up, mo',
                        description: '',
                        unit: '',
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_mean),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. Analyzed',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_analyzed),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Baseline',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_baseline),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Baseline CI / SE / SD*',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_baseline_ci),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Final or Delta**',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_final),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Final or Delta CI / SE / SD*',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
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

    main_more_than_two_dichotomous.each do |table|  #{{{2
        #table_headers = table[0]
        #outcome_measures = table_headers[4..-3]
        table = table[1..-1]
        unless table[0][0].blank?
            table.each do |row|
                arm = create_arm_if_needed(row[3], study)
                unless row[2].blank?
                    @h_outcome_title = row[2]
                    @h_unit = ""
#                    outcome = Outcome.create(
#                        study_id: study.id,
#                        title: row[2],
#                        is_primary: 1,
#                        units: "",
#                        description: row[3],
#                        notes: "",
#                        outcome_type: "Categorical",
#                        extraction_form_id: 194
#                    )
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Categorical", opts)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
#                    if t.nil?
#                        p @h_outcome_title
#                        p @h_unit
#                        p outcome
#                        p t
#                        p study
#                        p "-------------------------------------------------------------------------------"
#                    end
                    #s = OutcomeSubgroup.create(
                    #    outcome_id: outcome.id,
                    #    title: "All Participants",
                    #    description: "All participants involved in the study (Default)"
                    #)
                    @s = search_for_outcome_subgroup(outcome.id, row[2])
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: outcome.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: @s.id}).length + 1,
                        subgroup_id: @s.id
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

                    comparison = Comparison.create(
                        within_or_between: 'between',
                        study_id: study.id,
                        extraction_form_id: 194,
                        outcome_id: outcome.id,
                        group_id: t.id,
                        subgroup_id: @s.id,
                        section: 0
                    )
                    comparison_measure_p_between_groups = ComparisonMeasure.create(
                        title: 'P between groups***',
                        description: '',
                        unit: '',
                        note: '',
                        comparison_id: comparison.id,
                        measure_type: 1
                    )
                    comparison_measure_p_for_trend = ComparisonMeasure.create(
                        title: 'P for trend****',
                        description: '',
                        unit: '',
                        note: '',
                        comparison_id: comparison.id,
                        measure_type: 1
                    )
                    comparator = Comparator.create(
                        comparison_id: comparison.id,
                        comparator: "#{arm.id}_#{arm.id + 1}"
                    )
                    ComparisonDataPoint.create(
                        value: trans_yes_no_nd(row[12]),
                        footnote: nil,
                        is_calculated: nil,
                        comparison_measure_id: comparison_measure_p_between_groups.id,
                        comparator_id: comparator.id,
                        arm_id: 0,
                        footnote_number: 0,
                        table_cell: nil
                    )
                    ComparisonDataPoint.create(
                        value: trans_yes_no_nd(row[13]),
                        footnote: nil,
                        is_calculated: nil,
                        comparison_measure_id: comparison_measure_p_for_trend.id,
                        comparator_id: comparator.id,
                        arm_id: 0,
                        footnote_number: 0,
                        table_cell: nil
                    )
                else
#                    outcome = Outcome.find(:last, :conditions => {
#                        study_id: study.id,
#                        outcome_type: "Categorical",
#                        extraction_form_id: 194
#                    })
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Categorical", opts)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #s = OutcomeSubgroup.find(:last, :conditions => {
                    #    outcome_id: outcome.id,
                    #    title: "All Participants",
                    #    description: "All participants involved in the study (Default)"
                    #})
                    outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        subgroup_id: @s.id
                    })
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Vit D level/dose',
                    })
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
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(row[11]),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    comparison = Comparison.create(
                        within_or_between: 'between',
                        study_id: study.id,
                        extraction_form_id: 194,
                        outcome_id: outcome.id,
                        group_id: t.id,
                        subgroup_id: @s.id,
                        section: 0
                    )
                    comparison_measure_p_between_groups = ComparisonMeasure.create(
                        title: 'P between groups***',
                        description: '',
                        unit: '',
                        note: '',
                        comparison_id: comparison.id,
                        measure_type: 1
                    )
                    comparison_measure_p_for_trend = ComparisonMeasure.create(
                        title: 'P for trend****',
                        description: '',
                        unit: '',
                        note: '',
                        comparison_id: comparison.id,
                        measure_type: 1
                    )
                    comparator = Comparator.create(
                        comparison_id: comparison.id,
                        comparator: "#{arm.id}_#{arm.id + 1}"
                    )
                    ComparisonDataPoint.create(
                        value: trans_yes_no_nd(row[12]),
                        footnote: nil,
                        is_calculated: nil,
                        comparison_measure_id: comparison_measure_p_between_groups.id,
                        comparator_id: comparator.id,
                        arm_id: 0,
                        footnote_number: 0,
                        table_cell: nil
                    )
                    ComparisonDataPoint.create(
                        value: trans_yes_no_nd(row[13]),
                        footnote: nil,
                        is_calculated: nil,
                        comparison_measure_id: comparison_measure_p_for_trend.id,
                        comparator_id: comparator.id,
                        arm_id: 0,
                        footnote_number: 0,
                        table_cell: nil
                    )
                end
            end
        end
    end

    main_exactly_two_dichotomous.each do |table|  #{{{2
        unless table[2][0].blank?
            #table_headers_lv1 = table[0]
            #table_headers_lv2 = table[1]
            table_data = table[2..-1]
            table_data.each_with_index do |row, i|
                if i.even?
                    unless row[4].blank?
                        @h_outcome_title = row[2]
                        @h_unit = ""
                        h_exposure = row[3]
                        h_mean = row[4]
                        h_n_event = row[5]
                        h_n_total = row[6]
                        @h_outcome_metric = row[7]
                        h_unadjusted_result = row[8]
                        h_unadjusted_95_ci = row[9]
                        h_unadjusted_95_p_btw = row[10]
                        h_adjusted_result = row[11]
                        h_adjusted_95_ci = row[12]
                        h_adjusted__p_btw = row[13]

                        arm = create_arm_if_needed(arm_title=h_exposure, study)
                        ##        create_outcome_if_needed(outcome_title, unit, study, outcome_type)
                        #outcome = create_outcome_if_needed(row[2], "", study, "Categorical")
                        outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Categorical", opts)
                        t = OutcomeTimepoint.find(:last, :conditions => {
                            outcome_id: outcome.id,
                            #number: "N/A",
                            #time_unit: "N/A"
                        })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                        #s = OutcomeSubgroup.create(
                        #    outcome_id: outcome.id,
                        #    title: "All Participants",
                        #    description: "All participants involved in the study (Default)"
                        #)
                        @s = search_for_outcome_subgroup(outcome.id, row[2])
                        outcome_data_entry = OutcomeDataEntry.create(
                            outcome_id: outcome.id,
                            extraction_form_id: 194,
                            timepoint_id: t.id,
                            study_id: study.id,
                            display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: outcome.id,
                                                                                         extraction_form_id: 194,
                                                                                         timepoint_id: t.id,
                                                                                         study_id: study.id,
                                                                                         subgroup_id: @s.id}).length + 1,
                            subgroup_id: @s.id
                        )
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'Mean Follow-up, mo',
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_mean),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'N Event',
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_n_event),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'N Total',
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_n_total),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'Outcome Metric (e.g. OR, RR, HR, %) and direction of comparison*',
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(@h_outcome_metric),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )


                        comparison = Comparison.create(
                            within_or_between: 'between',
                            study_id: study.id,
                            extraction_form_id: 194,
                            outcome_id: outcome.id,
                            group_id: t.id,
                            subgroup_id: @s.id,
                            section: 0
                        )
                        comparison_measure_unadjusted_result = ComparisonMeasure.create(
                            title: 'Unadjusted - Result',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_unadjusted_95_ci = ComparisonMeasure.create(
                            title: 'Unadjusted - 95% CI',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_unadjusted_p_btw = ComparisonMeasure.create(
                            title: 'Unadjusted - P btw',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_adjusted_result = ComparisonMeasure.create(
                            title: 'Adjusted - Result',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_adjusted_95_ci = ComparisonMeasure.create(
                            title: 'Adjusted - 95% CI',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_adjusted_p_btw = ComparisonMeasure.create(
                            title: 'Adjusted - P btw',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )

                        comparator = Comparator.create(
                            comparison_id: comparison.id,
                            comparator: "#{arm.id}_#{arm.id + 1}"
                        )

                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_unadjusted_result),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_unadjusted_result.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_unadjusted_95_ci),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_unadjusted_95_ci.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_unadjusted_95_p_btw),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_unadjusted_p_btw.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_adjusted_result),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_adjusted_result.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_adjusted_95_ci),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_adjusted_95_ci.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_adjusted__p_btw),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_adjusted_p_btw.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                    end
                else
                    unless row[0].blank?
                        h_exposure = row[0]
                        h_mean = row[1]
                        h_n_event = row[2]
                        h_n_total = row[3]

                        arm = create_arm_if_needed(arm_title=h_exposure, study)
#                        outcome = Outcome.find(:last, :conditions => {
#                            study_id: study.id,
#                            outcome_type: "Categorical",
#                            extraction_form_id: 194
#                        })
                        outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Categorical", opts)
                        t = OutcomeTimepoint.find(:last, :conditions => {
                            outcome_id: outcome.id,
                        })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                        #s = OutcomeSubgroup.find(:last, :conditions => {
                        #    outcome_id: outcome.id,
                        #})
                        outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                            outcome_id: outcome.id,
                            extraction_form_id: 194,
                            timepoint_id: t.id,
                            study_id: study.id,
                            subgroup_id: @s.id
                        })
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'Outcome Metric (e.g. OR, RR, HR, %) and direction of comparison*',
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(@h_outcome_metric),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'N Total',
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_n_total),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'N Event',
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_n_event),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'Mean Follow-up, mo',
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_mean),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                    end
                end
            end
        end
    end

    sub_more_than_two_continuous.each do |table|  #{{{2
        unless table[1][4].blank?
            table_headers = table[0]
            outcome_measures = table_headers[5..-4]
            table = table[1..-1]
            table.each do |row|
                unless row[2].blank?  # This is a row with a new outcome
                    @h_outcome_title = row[2]
                    @h_unit = row[3]
                    ##        create_outcome_if_needed(outcome_title, unit, study, outcome_type)
                    #outcome = create_outcome_if_needed(row[2], row[3], study, "Continuous")
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Continuous", opts)
                    arm = create_arm_if_needed(arm_title=row[4], study)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #@s = OutcomeSubgroup.create(
                    #    outcome_id: outcome.id,
                    #    title: row[4],
                    #    description: ""
                    #)
                    @s = search_for_outcome_subgroup(outcome.id, row[2])
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: outcome.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: @s.id}).length + 1,
                        subgroup_id: @s.id
                    )
                    outcome_measures.each_with_index do |measure, i|
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: measure,
                            description: '',
                            unit: '',
                            note: nil,
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(row[i + 5]),
                            footnote: nil,
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                    end
                else
                    ##        find_last_outcome_created(study, outcome_type)
                    #outcome = find_last_outcome_created(study, "Continuous")
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Continuous", opts)
                    arm = create_arm_if_needed(arm_title=row[4], study)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #s = OutcomeSubgroup.find(:last, :conditions => {
                    #    outcome_id: outcome.id,
                    #})
                    outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        subgroup_id: @s.id
                    })
                    outcome_measures.each_with_index do |measure, i|
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: measure,
                            description: '',
                            unit: '',
                            note: nil,
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(row[i + 5]),
                            footnote: nil,
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                    end
                end
            end
        end
    end

    sub_exactly_two_continuous.each do |table|  #{{{2
        table = table[1..-1]
        table.each_with_index do |row, i|
            @h_unit = row[3] unless i.odd? #row[7].blank?
            if i.even?
                @h_outcome_title = row[2]
                @h_unit = row[3]
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
#                    _outcomes = Outcome.find(:all, :conditions => {
#                        study_id: study.id,
#                        extraction_form_id: 194
#                    })
#                    _outcomes.each do |out|
#                        if row[2].downcase.include?(out.title)
#                            outcome = Outcome.find(:first, :conditions => {
#                                study_id: study.id,
#                                title: out.title,
#                                outcome_type: 'Continuous',
#                                extraction_form_id: 194
#                            })
#                            @s = OutcomeSubgroup.create(
#                                outcome_id: outcome.id,
#                                title: row[2],
#                                description: row[4],
#                            )
#                            break
#                        end
#                    end
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Continuous", opts)
#                    begin
#                        p outcome
#                    rescue NameError => e
#                        p e
#                        outcome = Outcome.create(
#                            study_id: study.id,
#                            title: row[2],
#                            is_primary: 1,
#                            units: @h_unit,
#                            description: "",
#                            notes: "",
#                            outcome_type: "Continuous",
#                            extraction_form_id: 194
#                        )
#                        @s = OutcomeSubgroup.create(
#                            outcome_id: outcome.id,
#                            title: "All Participants",
#                            description: "All participants involved in the study (Default)"
#                        )
#                    end
                    #@s = OutcomeSubgroup.create(
                    #    outcome_id: outcome.id,
                    #    title: "All Participants",
                    #    description: "All participants involved in the study (Default)"
                    #)
                    @s = search_for_outcome_subgroup(outcome.id, h_outcome_title)
                    t = OutcomeTimepoint.find(:first, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: outcome.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: @s.id}).length + 1,
                        subgroup_id: @s.id
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
                        outcome_id: outcome.id,
                        group_id: t.id,
                        subgroup_id: @s.id,
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
                    if arm.blank?
                        arm = Arm.create(
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
                    #outcome = Outcome.find(:last, :conditions => {
                    #    study_id: study.id,
                    #    outcome_type: "Continuous",
                    #    extraction_form_id: 194
                    #})
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Continuous", opts)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #@s = OutcomeSubgroup.find(:last, :conditions => {
                    #    outcome_id: outcome.id,
                    #    title: "All Participants",
                    #    description: "All participants involved in the study (Default)"
                    #})
                    outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        subgroup_id: @s.id
                    })
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Follow-up, mo',
                        description: '',
                        unit: '',
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_mean),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'No. Analyzed',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_analyzed),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Baseline',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_baseline),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Baseline CI / SE / SD*',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_baseline_ci),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Final or Delta**',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
                    OutcomeDataPoint.create(
                        outcome_measure_id: om.id,
                        value: trans_yes_no_nd(h_final),
                        footnote: nil,
                        is_calculated: 0,
                        arm_id: arm.id,
                        footnote_number: 0
                    )
                    om = OutcomeMeasure.find(:last, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Final or Delta CI / SE / SD*',
                        description: 'Enter a Description Here',
                        unit: nil,
                        note: nil,
                        measure_type: 0
                    })
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

    sub_more_than_two_dichotomous.each do |table|  #{{{2
        table = table[1..-1]
        unless table.blank?
            table.each do |row|
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
                    @h_outcome_title = row[2]
                    @h_unit = ""
#                    _outcomes = Outcome.find(:all, :conditions => {
#                        study_id: study.id,
#                        extraction_form_id: 194
#                    })
#                    _outcomes.each do |out|
#                        if row[2].downcase.include?(out.title)
#                            outcome = Outcome.find(:first, :conditions => {
#                                study_id: study.id,
#                                title: out.title,
#                                is_primary: 1,
#                                outcome_type: "Categorical",
#                                extraction_form_id: 194
#                            })
#                            @s = OutcomeSubgroup.create(
#                                outcome_id: outcome.id,
#                                title: row[2],
#                                description: "All participants involved in the study (Default)"
#                            )
#                            break
#                        end
#                    end
#                    if outcome.blank?
#                        outcome = Outcome.create(
#                            study_id: study.id,
#                            title: row[2],
#                            is_primary: 1,
#                            units: "",
#                            description: row[3],
#                            notes: "",
#                            outcome_type: "Categorical",
#                            extraction_form_id: 194
#                        )
#                        @s = OutcomeSubgroup.create(
#                            outcome_id: outcome.id,
#                            title: row[2],
#                            description: "All participants involved in the study (Default)"
#                        )
#                    end
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Categorical", opts)
                    t = OutcomeTimepoint.find(:first, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #@s = OutcomeSubgroup.create(
                    #    outcome_id: outcome.id,
                    #    title: row[2],
                    #    description: "All participants involved in the study (Default)"
                    #)
                    @s = search_for_outcome_subgroup(outcome.id, row[2])
                    outcome_data_entry = OutcomeDataEntry.create(
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: outcome.id,
                                                                                     extraction_form_id: 194,
                                                                                     timepoint_id: t.id,
                                                                                     study_id: study.id,
                                                                                     subgroup_id: @s.id}).length + 1,
                        subgroup_id: @s.id
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
#                    outcome = Outcome.find(:last, :conditions => {
#                        study_id: study.id,
#                        outcome_type: "Categorical",
#                        extraction_form_id: 194
#                    })
                    outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Categorical", opts)
                    t = OutcomeTimepoint.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        #number: "N/A",
                        #time_unit: "N/A"
                    })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                    #@s = OutcomeSubgroup.find(:last, :conditions => {
                    #    outcome_id: outcome.id,
                    #    title: "All Participants",
                    #    description: "All participants involved in the study (Default)"
                    #})
                    outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                        outcome_id: outcome.id,
                        extraction_form_id: 194,
                        timepoint_id: t.id,
                        study_id: study.id,
                        subgroup_id: @s.id
                    })
                    om = OutcomeMeasure.find(:first, :conditions => {
                        outcome_data_entry_id: outcome_data_entry.id,
                        title: 'Mean Vit D level/dose',
                    })
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

    sub_exactly_two_dichotomous.each do |table|  #{{{2
        unless table[2][0].blank?
            #table_headers_lv1 = table[0]
            #table_headers_lv2 = table[1]
            table_data = table[2..-1]
            table_data.each_with_index do |row, i|
                if i.even?
                    unless row[4].blank?
                        @h_outcome_title = row[2]
                        @h_unit = ""
                        h_exposure = row[3]
                        h_mean = row[4]
                        h_n_event = row[5]
                        h_n_total = row[6]
                        @h_outcome_metric = row[7]
                        h_unadjusted_result = row[8]
                        h_unadjusted_95_ci = row[9]
                        h_unadjusted_95_p_btw = row[10]
                        h_adjusted_result = row[11]
                        h_adjusted_95_ci = row[12]
                        h_adjusted__p_btw = row[13]

                        arm = create_arm_if_needed(arm_title=h_exposure, study)
                        ##        create_outcome_if_needed(outcome_title, unit, study, outcome_type")
                        #outcome = create_outcome_if_needed(row[2], "", study, "Categorical")
                        outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Categorical", opts)
                        t = OutcomeTimepoint.find(:last, :conditions => {
                            outcome_id: outcome.id,
                            #number: "N/A",
                            #time_unit: "N/A"
                        })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                        #@s = OutcomeSubgroup.create(
                        #    outcome_id: outcome.id,
                        #    title: "All Participants",
                        #    description: "All participants involved in the study (Default)"
                        #)
                        @s = search_for_outcome_subgroup(outcome.id, row[2])
                        outcome_data_entry = OutcomeDataEntry.create(
                            outcome_id: outcome.id,
                            extraction_form_id: 194,
                            timepoint_id: t.id,
                            study_id: study.id,
                            display_number: OutcomeDataEntry.find(:all, :conditions => { outcome_id: outcome.id,
                                                                                         extraction_form_id: 194,
                                                                                         timepoint_id: t.id,
                                                                                         study_id: study.id,
                                                                                         subgroup_id: @s.id}).length + 1,
                            subgroup_id: @s.id
                        )
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'Mean Follow-up, mo',
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_mean),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'N Event',
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_n_event),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'N Total',
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_n_total),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.create(
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'Outcome Metric (e.g. OR, RR, HR, %) and direction of comparison*',
                            measure_type: 0
                        )
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(@h_outcome_metric),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )


                        comparison = Comparison.create(
                            within_or_between: 'between',
                            study_id: study.id,
                            extraction_form_id: 194,
                            outcome_id: outcome.id,
                            group_id: t.id,
                            subgroup_id: @s.id,
                            section: 0
                        )
                        comparison_measure_unadjusted_result = ComparisonMeasure.create(
                            title: 'Unadjusted - Result',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_unadjusted_95_ci = ComparisonMeasure.create(
                            title: 'Unadjusted - 95% CI',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_unadjusted_p_btw = ComparisonMeasure.create(
                            title: 'Unadjusted - P btw',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_adjusted_result = ComparisonMeasure.create(
                            title: 'Adjusted - Result',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_adjusted_95_ci = ComparisonMeasure.create(
                            title: 'Adjusted - 95% CI',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )
                        comparison_measure_adjusted_p_btw = ComparisonMeasure.create(
                            title: 'Adjusted - P btw',
                            description: '',
                            unit: '',
                            note: '',
                            comparison_id: comparison.id,
                            measure_type: 1
                        )

                        comparator = Comparator.create(
                            comparison_id: comparison.id,
                            comparator: "#{arm.id}_#{arm.id + 1}"
                        )

                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_unadjusted_result),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_unadjusted_result.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_unadjusted_95_ci),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_unadjusted_95_ci.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_unadjusted_95_p_btw),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_unadjusted_p_btw.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_adjusted_result),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_adjusted_result.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_adjusted_95_ci),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_adjusted_95_ci.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                        ComparisonDataPoint.create(
                            value: trans_yes_no_nd(h_adjusted__p_btw),
                            footnote: nil,
                            is_calculated: nil,
                            comparison_measure_id: comparison_measure_adjusted_p_btw.id,
                            comparator_id: comparator.id,
                            arm_id: 0,
                            footnote_number: 0,
                            table_cell: nil
                        )
                    end
                else
                    unless row[0].blank?
                        h_exposure = row[0]
                        h_mean = row[1]
                        h_n_event = row[2]
                        h_n_total = row[3]

                        arm = create_arm_if_needed(arm_title=h_exposure, study)
#                        outcome = Outcome.find(:last, :conditions => {
#                            study_id: study.id,
#                            outcome_type: "Categorical",
#                            extraction_form_id: 194
#                        })
                        outcome = search_for_outcome(study, @h_outcome_title, @h_unit, "Categorical", opts)
                        t = OutcomeTimepoint.find(:last, :conditions => {
                            outcome_id: outcome.id,
                        })
                    if t.nil?
                        p t
                        p study
                        p "-------------------------------------------------------------------------------"
                    end
                        #@s = OutcomeSubgroup.find(:last, :conditions => {
                        #    outcome_id: outcome.id,
                        #})
                        outcome_data_entry = OutcomeDataEntry.find(:last, :conditions => {
                            outcome_id: outcome.id,
                            extraction_form_id: 194,
                            timepoint_id: t.id,
                            study_id: study.id,
                            subgroup_id: @s.id
                        })
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'Outcome Metric (e.g. OR, RR, HR, %) and direction of comparison*',
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(@h_outcome_metric),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'N Total',
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_n_total),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'N Event',
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_n_event),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                        om = OutcomeMeasure.find(:last, :conditions => {
                            outcome_data_entry_id: outcome_data_entry.id,
                            title: 'Mean Follow-up, mo',
                            measure_type: 0
                        })
                        OutcomeDataPoint.create(
                            outcome_measure_id: om.id,
                            value: trans_yes_no_nd(h_mean),
                            is_calculated: 0,
                            arm_id: arm.id,
                            footnote_number: 0
                        )
                    end
                end
            end
        end
    end
end

## Splits up all the different kinds of result tables {{{1
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

## Creates a single arm named 'All Participants'. This is needed for cohort studies {{{1
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

## Determines whether this study is interventional or observational {{{1
## ARRAY ARRAY -> STRING
def find_outcome_type(quality_interventional, quality_case_control_studies)
    unless quality_interventional[1][0].blank?
        return "Categorical"
    end
    unless quality_case_control_studies[1][0].blank?
        return "Continuous"
    end
    p "WTF -- This thing is neither Categorical or Continuous!!!!"
    gets
end



if __FILE__ == $0  ## {{{1
    begin
        key_question_id_list = [356, 357, 358, 359, 360]
        table_array = Array.new
        pmids = Array.new
    
        validate_arg_list(opts)
    
        ## Load rails environment so we can access database object as well as use rails {{{2
        ## specific methods like blank?
        load_rails_environment
    
        doc = parse_html_file(opts[:file])
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
    
        ## Each study for this project has the pubmed ID recorded in almost every table under the
        ## `UI' heading. For the sake of simplicity and consistency we will retrieve the pmid from the
        ## `ELIGIBILITY CRITERIA AND OTHER CHARACTERISTICS' table
        pmid = retrieve_pmid_from_eligibility_table(eligibility)
        if pmid.blank?
            puts "*** ERROR ***"
            puts "No UI value found"
            puts "File name: #{opts[:file]}"
            #gets
            abort
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
    
        #{{{2
        ## Changed my mind about this one. We will create outcomes when we scan the results tables
        #outcome_type = find_outcome_type(quality_interventional, quality_case_control_studies)
        create_outcomes(study, outcomes)#, outcome_type)
        insert_outcome_detail_data(study, outcomes, comments)
        insert_confounders_info(study, confounders)  ## This is done actually
    
        ### Todo !!!
        build_results(study, doc, opts)  # !!!
    
        build_mean_data(study, mean) # !!!
        build_other_results(study, doc) # !!!
    rescue Exception => e
        p e
        File.open("fatal_errors.txt",'a') do |filea|
           filea.puts p opts[:file]
        end
    end
end
