WITH
    region_names AS (
    SELECT *
    FROM UNNEST([
      STRUCT<id STRING, name STRING>("africa-south1", "Johannesburg"),
      ("asia-east1", "Taiwan"),
      ("asia-east2", "Hong Kong"),
      ("asia-northeast1", "Tokyo"),
      ("asia-northeast2", "Osaka"),
      ("asia-northeast3", "Seoul"),
      ("asia-southeast1", "Singapore"),
      ("australia-southeast1", "Sydney"),
      ("australia-southeast2", "Melbourne"),
      ("europe-central2", "Warsaw"),
      ("europe-north1", "Finland"),
      ("europe-southwest1", "Madrid"),
      ("europe-west1", "Belgium"),
      ("europe-west2", "London"),
      ("europe-west3", "Frankfurt"),
      ("europe-west4", "Netherlands"),
      ("europe-west6", "Zurich"),
      ("europe-west8", "Milan"),
      ("europe-west9", "Paris"),
      ("europe-west10", "Berlin"),
      ("europe-west12", "Turin"),
      ("asia-south1", "Mumbai"),
      ("asia-south2", "Delhi"),
      ("asia-southeast2", "Jakarta"),
      ("me-central1", "Doha"),
      ("me-central2", "Dammam"),
      ("me-west1", "Tel Aviv"),
      ("northamerica-northeast1", "Montréal"),
      ("northamerica-northeast2", "Toronto"),
      ("us-central1", "Iowa"),
      ("us-east1", "South Carolina"),
      ("us-east4", "Northern Virginia"),
      ("us-east5", "Columbus"),
      ("us-south1", "Dallas"),
      ("us-west1", "Oregon"),
      ("us-west2", "Los Angeles"),
      ("us-west3", "Salt Lake City"),
      ("us-west4", "Las Vegas"),
      ("southamerica-east1", "São Paulo"),
      ("southamerica-west1", "Santiago")
    ])
    ),
    usage_cost_data AS (
    SELECT
      *,
      (
      SELECT
        AS STRUCT type,
        id,
        full_name
      FROM
        UNNEST(credits)
      WHERE
        type IN UNNEST(["COMMITTED_USAGE_DISCOUNT", "COMMITTED_USAGE_DISCOUNT_DOLLAR_BASE"])
      LIMIT
        1) AS cud,
      ARRAY( ( (
          SELECT
            AS STRUCT key AS key,
            value AS value,
            "label" AS x_type,
            FALSE AS x_inherited,
            "n/a" AS x_namespace
          FROM
            UNNEST(labels))
        UNION ALL (
          SELECT
            AS STRUCT key AS key,
            value AS value,
            "system_label" AS x_type,
            FALSE AS x_inherited,
            "n/a" AS x_namespace
          FROM
            UNNEST(system_labels))
        UNION ALL (
          SELECT
            AS STRUCT key AS key,
            value AS value,
            "project_label" AS x_type,
            TRUE AS x_inherited,
            "n/a" AS x_namespace
          FROM
            UNNEST(project.labels))
        UNION ALL (
          SELECT
            AS STRUCT key AS key,
            value AS value,
            "tag" AS x_type,
            inherited AS x_inherited,
            namespace AS x_namespace
          FROM
            UNNEST(tags) ) )) AS focus_tags,
    FROM
      `@{BILLING_TABLE}`), --updated table alias
      -- TODO - replace with your detailed usage export table path
    prices AS (
    SELECT
      *,
      flattened_prices
    FROM
      `@{PRICING_TABLE}`, -- updated pricing alias
      -- TODO - replace with your pricing export table path
      UNNEST(list_price.tiered_rates) AS flattened_prices
    WHERE
      DATE(export_time) = '@{DATE}')
      -- TODO - replace with a date after you enabled pricing export to use pricing data as of this date
  SELECT
    usage_cost_data.location.zone AS AvailabilityZone,
    CAST(usage_cost_data.cost AS NUMERIC) + IFNULL((
      SELECT
        SUM(CAST(c.amount AS NUMERIC))
      FROM
        UNNEST(usage_cost_data.credits) AS c), 0) AS BilledCost,
    "TODO - replace with the billing account ID in your detailed usage export table name" AS BillingAccountId,
    usage_cost_data.currency AS BillingCurrency,
    PARSE_TIMESTAMP("%Y%m", invoice.month, "America/Los_Angeles") AS BillingPeriodStart,
    TIMESTAMP(DATE_SUB(DATE_ADD(PARSE_DATE("%Y%m", invoice.month), INTERVAL 1 MONTH), INTERVAL 1 DAY), "America/Los_Angeles") AS BillingPeriodEnd,
    CASE LOWER(cost_type)
      WHEN "regular" THEN "usage"
      WHEN "tax" THEN "tax"
      WHEN "rounding_error" then "adjustment"
      WHEN "adjustment" then "adjustment"
      ELSE "error"
      END AS ChargeCategory,
    IF(
      COALESCE(
          usage_cost_data.adjustment_info.id,
          usage_cost_data.adjustment_info.description,
          usage_cost_data.adjustment_info.type,
          usage_cost_data.adjustment_info.mode)
        IS NOT NULL,
      "correction",
      NULL) AS ChargeClass,
    usage_cost_data.sku.description AS ChargeDescription,
    usage_cost_data.usage_start_time AS ChargePeriodStart,
    usage_cost_data.usage_end_time AS ChargePeriodEnd,
    CASE usage_cost_data.cud.type
      WHEN "COMMITTED_USAGE_DISCOUNT_DOLLAR_BASE" THEN "Spend"
      WHEN "COMMITTED_USAGE_DISCOUNT" THEN "Usage"
      END AS CommitmentDiscountCategory,
    usage_cost_data.subscription.instance_id AS CommitmentDiscountId,
    usage_cost_data.cud.full_name AS CommitmentDiscountName,
    IF(usage_cost_data.cost_type = "regular", CAST(usage_cost_data.usage.amount AS NUMERIC), NULL) AS ConsumedQuantity,
    IF(usage_cost_data.cost_type = "regular", usage_cost_data.usage.unit, NULL) AS ConsumedUnit,
    CAST(usage_cost_data.cost AS NUMERIC) AS ContractedCost,
    CAST(usage_cost_data.price.effective_price AS NUMERIC) AS ContractedUnitPrice,
    CAST(usage_cost_data.cost AS NUMERIC) + IFNULL((
      SELECT
        SUM(CAST(c.amount AS NUMERIC))
      FROM
        UNNEST(usage_cost_data.credits) AS c), 0) AS EffectiveCost,
    CAST(usage_cost_data.cost_at_list AS NUMERIC) AS ListCost,

    IF(usage_cost_data.cost_type = "regular", CAST(prices.flattened_prices.account_currency_amount AS NUMERIC), NULL
  ) AS ListUnitPrice,
    IF(
      usage_cost_data.cost_type = "regular",
      IF(
        LOWER(usage_cost_data.sku.description) LIKE "commitment%" OR usage_cost_data.cud IS NOT NULL,
        "committed",
        "standard"),
      null) AS PricingCategory,
    IF(usage_cost_data.cost_type = "regular", usage_cost_data.price.pricing_unit_quantity, NULL) AS PricingQuantity,
    IF(usage_cost_data.cost_type = "regular", usage_cost_data.price.unit, NULL) AS PricingUnit,
    "Google Cloud" AS ProviderName,
    IF(usage_cost_data.transaction_type = "GOOGLE", "Google Cloud", usage_cost_data.seller_name) AS PublisherName,
    usage_cost_data.location.region AS RegionId,
    (
    SELECT
      name
    FROM
      region_names
    WHERE
      id = usage_cost_data.location.region) AS RegionName,
    usage_cost_data.resource.global_name AS ResourceId,
    usage_cost_data.resource.name AS ResourceName,
    IF(
      STARTS_WITH( usage_cost_data.resource.global_name, '//'),
      REGEXP_REPLACE(
        usage_cost_data.resource.global_name,
        '(//)|(googleapis.com/)|(projects/[^/]+/)|(project_commitments/[^/]+/)|(locations/[^/]+/)|(regions/[^/]+/)|(zones/[^/]+/)|(global/)|(/[^/]+)',
        ''),
      NULL) AS ResourceType,
    prices.product_taxonomy AS ServiceCategory,
    usage_cost_data.service.description AS ServiceName,
    IF(usage_cost_data.cost_type = "regular", usage_cost_data.sku.id, NULL) AS SkuId,
    IF(
      usage_cost_data.cost_type = "regular",
      CONCAT(
        "Billing Account ID:", usage_cost_data.billing_account_id,
        ", SKU ID: ", usage_cost_data.sku.id,
        ", Price Tier Start Amount: ", price.tier_start_amount),
      NULL) AS SkuPriceId,
    usage_cost_data.billing_account_id as SubAccountId,
    usage_cost_data.focus_tags AS Tags,
    ARRAY((
      SELECT
        AS STRUCT name AS Name,
        CAST(amount AS NUMERIC) AS Amount,
        full_name AS FullName,
        id AS Id,
        type AS Type
      FROM
        UNNEST(usage_cost_data.credits))) AS x_Credits,
    usage_cost_data.cost_type AS x_CostType,
    CAST(usage_cost_data.currency_conversion_rate AS NUMERIC) AS x_CurrencyConversionRate,
    usage_cost_data.export_time AS x_ExportTime,
    usage_cost_data.location.location AS x_Location,
    (
    SELECT
      AS STRUCT usage_cost_data.project.id,
      usage_cost_data.project.number,
      usage_cost_data.project.name,
      usage_cost_data.project.ancestry_numbers,
      usage_cost_data.project.ancestors) AS x_Project,
    usage_cost_data.service.id AS x_ServiceId
  FROM
    usage_cost_data
  LEFT JOIN
    prices
  ON
    usage_cost_data.sku.id = prices.sku.id
    AND usage_cost_data.price.tier_start_amount = prices.flattened_prices.start_usage_amount;