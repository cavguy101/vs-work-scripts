LOAD DATA 
INFILE '$APPLCSF/$APPLLOG/thirdpartydeductions.csv'
BADFILE '$APPLCSF/$APPLLOG/thirdpartydeductions.bad'
DISCARDFILE '$APPLCSF/$APPLLOG/thirdpartydeductions.dsc'
APPEND 
INTO TABLE AP_INVOICES_INTERFACE
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
invoice_id                             	CHAR,
invoice_date                            DATE,
vendor_id	                            CHAR,
vendor_site_id	                        CHAR,
terms_date                              DATE,
invoice_amount                          DECIMAL EXTERNAL,
gl_date                                 DATE, 
invoice_num                             CHAR,
operating_unit                          CONSTANT 'XX-OU',
org_id                                  CONSTANT  82,
invoice_type_lookup_code                CONSTANT 'STANDARD',
invoice_currency_code                   CONSTANT 'TTD',
terms_name                              CONSTANT 'IMMEDIATE',
creation_date                           SYSDATE,
created_by                              CONSTANT 0,
source                                  CONSTANT 'XXPAYROLLTHIRDPARTY',    
payment_method_code                     CONSTANT 'CHECK'
)

INTO TABLE AP_INVOICE_LINES_INTERFACE
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
invoice_id                              CHAR,
amount                                  DECIMAL EXTERNAL,
distribution_set_name                   CHAR,
line_number                             CONSTANT 1,
line_type_lookup_code                   CONSTANT 'ITEM',
accounting_date                         SYSDATE,
ship_to_location_code                   CONSTANT 'HO',
creation_date                           SYSDATE,
created_by                              CONSTANT 0
)
