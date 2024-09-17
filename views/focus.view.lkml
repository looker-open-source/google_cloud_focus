view: focus {
  derived_table: {
    datagroup_trigger: daily_datagroup
    sql:
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
    AND usage_cost_data.price.tier_start_amount = prices.flattened_prices.start_usage_amount;;

  }

  dimension: availability_zone {
    type: string
    description: "An availability zone is a provider-assigned identifier for a physically separated and isolated area within a
    Region that provides high availability and fault tolerance."
    sql: ${TABLE}.AvailabilityZone ;;
  }

  dimension: billed_cost {
    type: number
    description: "Billed cost represents a charge serving as the basis for invoicing, inclusive of the impacts of all reduced
    rates and discounts while excluding the amortization of relevant purchases (one-time or recurring) paid to
    cover future eligible charges. "
    sql: ${TABLE}.BilledCost ;;
    value_format_name: usd_0
  }

  dimension: billing_account_id {
    type: string
    description: "A Billing Account ID is a provider-assigned identifier for a billing account."
    sql: ${TABLE}.BillingAccountId ;;
  }

  dimension: billing_currency {
    type: string
    description: "Billing currency is an identifier that represents the currency that a charge forresources or services was
    billed in."
    sql: ${TABLE}.BillingCurrency ;;
  }

  dimension_group: billing_period_start {
    type: time
    description: "Billing Period Start represents the inclusive start date and time of a billing period."
    timeframes: [
      date,
      week,
      month,
      quarter,
      year
    ]
    datatype: datetime
    sql: ${TABLE}.BillingPeriodStart;;
  }

  dimension_group: billing_period_end {
    type: time
    description: "Billing Period End represents the inclusive end date and time of a billing period."
    timeframes: [
      date,
      week,
      month,
      quarter,
      year
    ]
    datatype: datetime
    sql: ${TABLE}.BillingPeriodEnd;;
  }

  dimension: charge_category {
    type: string
    description: "Charge category represents the highest-level classification of a charge based on the nature of how it is
    billed. Charge Category is commonly used to identify and distinguish between types of charges that may
    require different handling."
    sql: ${TABLE}.ChargeCategory;;
  }

  dimension: charge_class {
    type: string
    description: "Charge Class indicates whether the row represents a correction to one or more charges invoiced in a
    previous billing period. Charge Class is commonly used to differentiate corrections from regularly incurred
    charges."
    sql: ${TABLE}.ChargeClass ;;
  }

  dimension: charge_description {
    type: string
    description: "A Charge Description provides a high-level context of a row without requiring additional discovery."
    sql: ${TABLE}.ChargeDescription ;;
  }

  dimension_group: charge_period_start {
    type: time
    description: "Charge Period Start represents the inclusive start date and time within a charge period."
    timeframes: [
      date,
      week,
      month,
      quarter,
      year
    ]
    sql: ${TABLE}.ChargePeriodStart ;;
  }

  dimension_group: charge_period_end {
    type: time
    description: "Charge Period End represents the exclusive end date and time of a charge period."
    timeframes: [
      date,
      week,
      month,
      quarter,
      year
    ]
    sql: ${TABLE}.ChargePeriodEnd ;;
  }

  dimension: commitment_discount_category {
    type: string
    description: "Commitment Discount Category indicates whether the commitment-based discount identified in the
    CommitmentDiscountId column is based on usage quantity or cost (aka spend)."
    group_label: "CUDs"
    sql: ${TABLE}.CommitmentDiscountCategory ;;
  }

  dimension: commitment_discount_id {
    type: string
    description: "A Commitment Discount ID is the identifier assigned to a commitment-based discount by the provider."
    group_label: "CUDs"
    sql: ${TABLE}.CommitmentDiscountId ;;
  }

  dimension: commitment_discount_name {
    type: string
    description: "A Commitment Discount Name is the display name assigned to a commitment-based discount."
    group_label: "CUDs"
    sql: ${TABLE}.CommitmentDiscountName ;;
  }

  dimension: consumed_quantity {
    type: number
    description: "The Consumed Quantity represents the volume of a given SKU associated with a resource or service used,
    based on the Consumed Unit"
    sql: ${TABLE}.ConsumedQuantity ;;
  }

  dimension: consumed_unit {
    type: string
    description: "The Consumed Unit represents a provider-specified measurement unit indicating how a provider measures
    usage of a given SKU associated with a resource or service. "
    sql:${TABLE}.ConsumedUnit ;;
  }

  dimension: contracted_cost {
    type: number
    description: "Contracted Cost represents the cost calculated by multiplying contracted unit price and the corresponding
    Pricing Quantity"
    sql: ${TABLE}.ContractedCost ;;
    value_format_name: usd_0
  }

  dimension: contracted_unit_price {
    type: number
    description: "The Contracted Unit Price represents the agreed-upon unit price for a singlePricing Unit of the associated
    SKU, inclusive of negotiated discounts, if present, while excluding negotiated commitment-based discounts
    or any other discounts"
    sql: ${TABLE}.ContractedUnitPrice ;;
    value_format_name: usd_0
  }

  dimension: effective_cost {
    type: number
    description: "Effective Cost represents the amortized cost of the charge after applying all reduced rates, discounts, and
    the applicable portion of relevant, prepaid purchases (one-time or recurring) that covered this charge."
    sql: ${TABLE}.EffectiveCost ;;
    value_format_name: usd_0
  }

  dimension: list_cost {
    type: number
    description: "List Cost represents the cost calculated by multiplying the list unit price and the corresponding Pricing Quantity."
    hidden: yes
    sql: ${TABLE}.ListCost ;;
    value_format_name: usd_0
  }

  dimension: list_unit_price {
    type: string
    description: "The List Unit Price represents the suggested provider-published unit price for a single Pricing Unit of the
    associated SKU, exclusive of any discounts."
    sql: ${TABLE}.ListUnitPrice ;;
    value_format_name: usd_0
  }
  dimension: pricing_category {
    type: string
    description: "The Pricing Category describes the pricing model used for a charge at the time of use or purchase."
    sql: ${TABLE}.PricingCategory ;;
  }

  dimension: pricing_quantity {
    type: number
    description: "The Pricing Quantity represents the volume of a given SKU associated with a resource or service used or
    purchased, based on the Pricing Unit."
    sql: ${TABLE}.PricingQuantity ;;
  }

  dimension: pricing_unit {
    type: string
    description: "The Pricing Unit represents a provider-specified measurement unit for determining unit prices, indicating
    how the provider rates measured usage and purchase quantities after applying pricing rules like block
    pricing. "
    sql: ${TABLE}.PricingUnit ;;
  }

  dimension: provider_name {
    type: string
    description: "A Provider is an entity that makes the resources or services available for purchase."
    sql: ${TABLE}.ProviderName ;;
  }

  dimension: publisher_name {
    type: string
    description: "A Publisher is an entity that produces the resources or services that were purchased."
    sql: ${TABLE}.PublisherName ;;
  }

  dimension: region_id {
    type: string
    description: "A Region ID is a provider-assigned identifier for an isolated geographic area where aresource is provisioned
    or a service is provided."
    sql: ${TABLE}.RegionId ;;
  }

  dimension: region_name {
    type: string
    description: "Region Name is a provider-assigned display name for an isolated geographic area where aresource is
    provisioned or a service is provided."
    sql: ${TABLE}.RegionName ;;
  }

  dimension: resource_id {
    type: string
    description: "A Resource ID is an identifier assigned to a resource by the provider."
    sql: ${TABLE}.ResourceId ;;
  }

  dimension: resource_name {
    type: string
    description: "The Resource Name is a display name assigned to aresource."
    sql: ${TABLE}.ResourceName ;;
  }

  dimension: resource_type {
    type: string
    description: "The Resource Type describes the kind of resource the charge applies to."
    sql: ${TABLE}.ResourceType ;;
  }

  dimension: service_category {
    type: string
    description: "The Service Category is the highest-level classification of a service based on the core function of the service."
    hidden: yes
    sql: ${TABLE}.ServiceCategory ;;
  }

  dimension: service_name {
    type: string
    description: "A service represents an offering that can be purchased from a provider (e.g., cloud virtual machine, SaaS database, professional services from a systems integrator)."
    sql: ${TABLE}.ServiceName ;;
  }

  dimension: sku_id {
    type: string
    description: "A SKU ID is a unique identifier that defines a provider-supported construct for organizing properties that are
    common across one or more SKU Prices."
    sql: ${TABLE}.SkuId ;;
  }

  dimension: sku_price_id {
    type: string
    description: "A SKU Price ID is a unique identifier that defines the unit price used to calculate the charge."
    sql: ${TABLE}.SkuPriceId ;;
  }

  dimension: sub_account_id {
    type: string
    description: "A Sub Account ID is a provider-assigned identifier assigned to a sub account."
    sql: ${TABLE}.SubAccountId ;;
  }

  dimension: tags {
    type: string
    description: "The Tags column represents the set of tags assigned
    to tag sources that also account for potential providerdefined or user-defined tag evaluations."
    hidden: yes
    sql: ${TABLE}.Tags ;;
  }

  # dimension: usage_amount {
  #   type: string
  #   hidden: yes
  #   sql: ${TABLE}.UsageAmount ;;
  # }

  # dimension: gc_cost {
  #   type: number
  #   group_label: "Google Cloud Fields"
  #   label: "Google Cloud Cost"
  #   hidden: yes
  #   sql: ${TABLE}.gc_Cost ;;
  # }

  # dimension: gc_credits {
  #   type: string
  #   hidden: yes
  #   sql: ${TABLE}.gc_Credits ;;
  # }

  # dimension: gc_cost_type {
  #   type: string
  #   group_label: "Google Cloud Fields"
  #   label: "Google Cloud Cost Type"
  #   sql: ${TABLE}.gc_CostType ;;
  # }

  ###### MEASURES ######
  measure: total_list_cost {
    type: sum
    description: "Total List Cost represents the cost calculated by summing the multiplied list unit price and the corresponding Pricing
    Quantity."
    value_format_name: usd_0
    sql: ${list_cost} ;;
  }

  # measure: total_gc_cost {
  #   type: sum
  #   group_label: "Google Cloud Fields"
  #   label: "Total Google Cloud Cost"
  #   value_format_name: usd_0
  #   sql: ${gc_cost} ;;
  # }

  # measure: total_usage_amount {
  #   type: sum
  #   description: "The Consumed Quantity represents the volume of a given SKU associated with a resource or service used,
  #   based on the Consumed Unit."
  #   value_format_name: decimal_0
  #   sql: ${usage_amount} ;;
  # }
}

view: gc_Credits {
  view_label: "Focus"

  dimension: amount {
    type: number
    hidden: yes
    sql: ${TABLE}.amount ;;
  }

  dimension: full_name {
    type: string
    group_label: "Google Cloud Credits"
    sql: ${TABLE}.fullname ;;
  }

  dimension: id {
    type: string
    group_label: "Google Cloud Credits"
    sql: ${TABLE}.id ;;
  }

  dimension: name {
    type: string
    group_label: "Google Cloud Credits"
    sql: ${TABLE}.name ;;
  }

  dimension: type {
    type: string
    group_label: "Google Cloud Credits"
    sql: ${TABLE}.type ;;
  }

  measure: total_amount {
    type: sum
    label: "Google Cloud Credit Amount"
    group_label: "Google Cloud Fields"
    value_format_name: usd_0
    sql: ${amount} ;;
  }
}

view: ServiceCategory {
  view_label: "Focus"

  dimension: service_category {
    type: string
    description: "The Service Category is the highest-level classification of a service based on the core function of the service."
    sql: ${TABLE} ;;
  }
}

view: tags {
  view_label: "Focus"

  dimension: inherited {
    type: yesno
    group_label: "Tags"
    sql: ${TABLE}.x_inherited ;;
  }

  dimension: key {
    type: string
    group_label: "Tags"
    sql:  ${TABLE}.key ;;
  }

  dimension: namespace {
    type: string
    group_label: "Tags"
    sql:  ${TABLE}.x_namespace ;;
  }

  dimension: type {
    type: string
    group_label: "Tags"
    sql:  ${TABLE}.x_type ;;
  }

  dimension: value {
    type: string
    group_label: "Tags"
    sql:  ${TABLE}.value ;;
  }
}
