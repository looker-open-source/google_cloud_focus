include: "/views/*.view.lkml"

explore: focus {
  # join: gc_Credits {
  #   sql:  LEFT JOIN UNNEST(${focus.gc_credits}) as gc_Credits ;;
  #   relationship: one_to_many
  # }
  join: ServiceCategory {
    sql: LEFT JOIN UNNEST(${focus.service_category}) as ServiceCategory ;;
    relationship: one_to_many
  }
  join: tags {
    sql: LEFT JOIN UNNEST(${focus.tags}) as tags ;;
    relationship: one_to_many
  }
}
