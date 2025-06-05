import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import boto3
import logging
import time
import os
from io import StringIO
import re

args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'source_s3_path',
    'table_namespace', 
    'table_name',
    'table_bucket_arn'
])

sc = SparkContext()
glueContext = GlueContext(sc)
logger = glueContext.get_logger()
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

SOURCE_S3_PATH = args['source_s3_path']
TABLE_NAMESPACE = args['table_namespace']
TABLE_NAME = args['table_name']
TABLE_BUCKET_ARN = args['table_bucket_arn']
TABLE_BUCKET_NAME = TABLE_BUCKET_ARN.split('/')[-1]
ACCOUNT_ID = TABLE_BUCKET_ARN.split(':')[4]
REGION = TABLE_BUCKET_ARN.split(':')[3]


def slugify(name):
    name = name.lower()
    name = re.sub(r'[^a-z0-9]+', '_', name)
    name = re.sub(r'_+', '_', name)
    return name.strip('_')


def main():
    
    logger.info(f"Configured Spark session for S3 Tables:")
    logger.info(f"  - Account ID: {ACCOUNT_ID}")
    logger.info(f"  - Table Bucket: {TABLE_BUCKET_NAME}")
    logger.info(f"  - Catalog ID: {ACCOUNT_ID}:s3tablescatalog/{TABLE_BUCKET_NAME}")
    logger.info(f"  - Warehouse: s3://{TABLE_BUCKET_NAME}/warehouse/")
    logger.info(f"  - Namespace: {TABLE_NAMESPACE}")
    
    spark = SparkSession.builder.appName("SparkIcebergSQL") \
       .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
       .config("spark.sql.defaultCatalog", "s3tables") \
       .config("spark.sql.catalog.s3tables", "org.apache.iceberg.spark.SparkCatalog") \
       .config("spark.sql.catalog.s3tables.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog") \
       .config("spark.sql.catalog.s3tables.glue.id", f"{ACCOUNT_ID}:s3tablescatalog/{TABLE_BUCKET_NAME}") \
       .config("spark.sql.catalog.s3tables.warehouse", f"s3://{TABLE_BUCKET_NAME}/warehouse/") \
       .getOrCreate()  

    logger.info(f"Reading CSV data from: {SOURCE_S3_PATH}")
    dynamic_frame = glueContext.create_dynamic_frame.from_options(
        format_options={
            "quoteChar": '"',
            "withHeader": True,
            "separator": ",",
            "optimizePerformance": False,
        },
        connection_type="s3",
        format="csv",
        connection_options={
            "paths": [SOURCE_S3_PATH],
            "recurse": True
        },
        transformation_ctx="read_csv"
    )
    
    if dynamic_frame.count() == 0:
        logger.info("No data found in source path. Exiting.")
        return
    else:
        logger.info(f"CSV data loaded. Record count: {dynamic_frame.count()}")
    
    df = dynamic_frame.toDF()
    df = df.dropna(how='all')
    
    logger.info(f"Writing data to S3 Table: {TABLE_NAMESPACE}.{TABLE_NAME}")
    
    # Create database if it doesn't exist
    spark.sql(f"CREATE DATABASE IF NOT EXISTS {TABLE_NAMESPACE}")
    
    columns = df.dtypes
    columns_sql = ", ".join([f"{slugify(name)} {dtype.upper()}" for name, dtype in columns])
    logger.info(f"Columns: {columns_sql}")

    table_identifier = f"{TABLE_NAMESPACE}.{TABLE_NAME}"
    
    create_table_sql = f"""
        CREATE TABLE IF NOT EXISTS {table_identifier} (
            {columns_sql}
        )
    """

    logger.info(f"Creating table if not exists with SQL:\n{create_table_sql}")
    spark.sql(create_table_sql)
    logger.info(f"Table created: {table_identifier}")
        
    time.sleep(16)
    
    df.createOrReplaceTempView("temp_data_to_insert")
    logger.info(f"Inserting data into {table_identifier}...")
    insert_sql = f"""
        INSERT INTO {table_identifier}
        SELECT * FROM temp_data_to_insert
    """
    spark.sql(insert_sql)

    count_result = spark.sql(f"SELECT COUNT(*) as count FROM {table_identifier}").collect()
    record_count = count_result[0]['count']
    
    logger.info(f"Successfully wrote data to S3 Table: {table_identifier}")
    logger.info(f"Total records in table: {record_count}")

    spark.sql(f"select * from {table_identifier}").show()

if __name__ == "__main__":
    main()

