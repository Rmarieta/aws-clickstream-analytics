# ===========================================================================
# Glue Data Catalog for Athena queries on S3 Parquet data
#
# This module creates:
# 1. A Glue database for clickstream data
# 2. A Glue table with the events schema (used by Firehose for Parquet
#    format conversion and by Athena for querying)
# ===========================================================================

resource "aws_glue_catalog_database" "this" {
  name        = var.database_name
  description = "Clickstream analytics data lake"
}

resource "aws_glue_catalog_table" "events" {
  name          = var.table_name
  database_name = aws_glue_catalog_database.this.name
  description   = "Clickstream events in Parquet format, partitioned by date/hour"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification"        = "parquet"
    "parquet.compression"   = "SNAPPY"
    "projection.enabled"    = "true"
    "projection.year.type"  = "integer"
    "projection.year.range" = "2024,2030"
    "projection.month.type" = "integer"
    "projection.month.range"= "1,12"
    "projection.month.digits"= "2"
    "projection.day.type"   = "integer"
    "projection.day.range"  = "1,31"
    "projection.day.digits" = "2"
    "projection.hour.type"  = "integer"
    "projection.hour.range" = "0,23"
    "projection.hour.digits"= "2"
    "storage.location.template" = "s3://${var.raw_bucket_name}/data/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}/"
  }

  storage_descriptor {
    location      = "s3://${var.raw_bucket_name}/data/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    # Event schema columns (must match the simulator output)
    columns {
      name = "event_id"
      type = "string"
    }
    columns {
      name = "timestamp"
      type = "string"
    }
    columns {
      name = "user_id"
      type = "string"
    }
    columns {
      name = "session_id"
      type = "string"
    }
    columns {
      name = "page_url"
      type = "string"
    }
    columns {
      name = "page_category"
      type = "string"
    }
    columns {
      name = "event_type"
      type = "string"
    }
    columns {
      name = "referrer"
      type = "string"
    }
    columns {
      name = "device"
      type = "string"
    }
    columns {
      name = "browser"
      type = "string"
    }
    columns {
      name = "os"
      type = "string"
    }
    columns {
      name = "country"
      type = "string"
    }
    columns {
      name = "city"
      type = "string"
    }
    # Fields added by Firehose transform Lambda
    columns {
      name = "processed_at"
      type = "string"
    }
    columns {
      name = "processing_lag_ms"
      type = "int"
    }
  }

  # Partition keys for Hive-style partitioning
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }
}

# ===========================================================================
# Athena workgroup for query execution
# ===========================================================================
resource "aws_athena_workgroup" "this" {
  name        = "${var.name_prefix}-workgroup"
  description = "Workgroup for clickstream analytics queries"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.raw_bucket_name}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  force_destroy = true
}
