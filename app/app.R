library(shiny)
library(DBI)
library(RSQLite)
library(dplyr)
library(leaflet)
library(tidygeocoder)
library(ggplot2)
library(httr)
library(jsonlite)

# Connect to SQLite
conn <- dbConnect(RSQLite::SQLite(), dbname = "parks.db")

activity_lookup <- dbReadTable(conn, "activity_lookup")
park_activities <- dbReadTable(conn, "park_activities")
amenities <- dbReadTable(conn, "amenities")
park_amenities <- dbReadTable(conn, "park_amenities")
parks <- dbReadTable(conn, "parks")

activities <- left_join(park_activities, activity_lookup, by = "activity_id")
amenities <- left_join(park_amenities, amenities, by = "amenity_id")

# State dictionary (unchanged)
state_dict <- c(
  "AL"="Alabama", "AK"="Alaska", "AZ"="Arizona", "AR"="Arkansas", "CA"="California",
  "CO"="Colorado", "CT"="Connecticut", "DC"="District of Columbia", "DE"="Delaware",
  "FL"="Florida", "GA"="Georgia", "HI"="Hawaii", "ID"="Idaho", "IL"="Illinois",
  "IN"="Indiana", "IA"="Iowa", "KS"="Kansas", "KY"="Kentucky", "LA"="Louisiana",
  "ME"="Maine", "MD"="Maryland", "MA"="Massachusetts", "MI"="Michigan",
  "MN"="Minnesota", "MS"="Mississippi", "MO"="Missouri", "MT"="Montana",
  "NE"="Nebraska", "NV"="Nevada", "NH"="New Hampshire", "NJ"="New Jersey",
  "NM"="New Mexico", "NY"="New York", "NC"="North Carolina", "ND"="North Dakota",
  "OH"="Ohio", "OK"="Oklahoma", "OR"="Oregon", "PA"="Pennsylvania",
  "RI"="Rhode Island", "SC"="South Carolina", "SD"="South Dakota",
  "TN"="Tennessee", "TX"="Texas", "UT"="Utah", "VT"="Vermont", "VA"="Virginia",
  "WA"="Washington", "WV"="West Virginia", "WI"="Wisconsin", "WY"="Wyoming",
  "PR"="Puerto Rico", "GU"="Guam", "VI"="U.S. Virgin Islands", "AS"="American Samoa",
  "MP"="Northern Mariana Islands"
)

parks$states <- state_dict[parks$states]

css_code <- HTML("
  .leaflet-popup-content-wrapper {
    max-height: 200px;
    overflow-y: auto;
  }
  .leaflet-popup-content {
    width: 300px !important;
  }
")

# ------------------------------
#        UI LAYOUT
# ------------------------------
ui <- fluidPage(
  titlePanel("United States National Parks"),
  sidebarLayout(
    sidebarPanel(
      width = 2,
      style = "width:220px; margin-top: 0; padding-top: 0; padding-right:5px; 
               background-color:#f9f9f9; border-radius:8px; 
               box-shadow:0px 2px 4px rgba(0,0,0,0.05);",

      selectInput(
        "mapFilter", "States and U.S. Territories",
        choices = sort(unique(parks$states)),
        multiple = TRUE
      ),

      radioButtons(
        "activityLogic", "Show Activities:",
        choices = c("AND" = "and", "OR" = "or"),
        selected = "or", inline = TRUE
      ),

      selectInput(
        "activityFilter", "Activities",
        choices = sort(unique(activities$activity_name)),
        multiple = TRUE
      ),

      radioButtons(
        "amenityLogic", "Show Amenities:",
        choices = c("AND" = "and", "OR" = "or"),
        selected = "or", inline = TRUE
      ),

      selectInput(
        "amenityFilter", "Amenities",
        choices = sort(unique(amenities$amenity_name)),
        multiple = TRUE
      )
    ),

    mainPanel(
      tags$head(tags$style(css_code)),
      leafletOutput("myMap", height = "500px"),
      br(),

      fluidRow(
        column(
          width = 4,
          div(
            style = "background-color:#f8f9fa; border-radius:10px; padding:15px;
                     box-shadow:0px 2px 4px rgba(0,0,0,0.1); min-height:340px;",
            h3("AI-Generated Summary"),
            div(
              style = "background:white; padding:12px; border-radius:8px; 
                       height:280px; overflow-y:auto; font-size:15px; 
                       line-height:1.5; color:#222; border:1px solid #ddd;",
              textOutput("llmSummary")
            )
          )
        ),

        column(
          width = 4,
          div(
            style = "background-color:#f8f9fa; border-radius:10px; padding:15px;
                     box-shadow:0px 2px 4px rgba(0,0,0,0.1);",
            h3("Top 10 Activities"),
            plotOutput("activityPlot", height = "300px")
          )
        ),

        column(
          width = 4,
          div(
            style = "background-color:#f8f9fa; border-radius:10px; padding:15px;
                     box-shadow:0px 2px 4px rgba(0,0,0,0.1);",
            h3("Top 10 Amenities"),
            plotOutput("amenityPlot", height = "300px")
          )
        )
      )
    )
  )
)

# ------------------------------
#   LLM SUMMARY FUNCTION
# ------------------------------
Sys.getenv("OPENROUTER_API_KEY")

generate_llm_explanation <- function(states, activities, amenities) {

  state_text <- ifelse(length(states) == 0,
                       "the entire United States",
                       paste(states, collapse = ", "))

  prompt <- paste0(
    "You are an expert park analyst.\n",
    "Summarize the key characteristics of these parks activities and amenities.\n",
    "Region: ", state_text, ".\n",
    "Top activities: ", paste(activities, collapse = ", "), ".\n",
    "Top amenities: ", paste(amenities, collapse = ", "), ".\n",
    "Write a short, human-readable explanation in 2–3 sentences, including the information of state."
  )

  res <- POST(
    "https://openrouter.ai/api/v1/chat/completions",
    add_headers(
      Authorization = paste("Bearer", Sys.getenv("OPENROUTER_API_KEY")),
      "Content-Type" = "application/json"
    ),
    body = toJSON(list(
      model = "qwen/qwen3-235b-a22b:free",
      messages = list(list(
        role = "user",
        content = prompt
      ))
    ), auto_unbox = TRUE)
  )

  txt <- content(res, "text", encoding = "UTF-8")

  # Try to parse JSON, safely
  result <- tryCatch(
    fromJSON(txt, simplifyVector = FALSE),
    error = function(e) return(NULL)
  )

  # If JSON failed or structure isn't right
  if (is.null(result) ||
      is.null(result$choices) ||
      is.null(result$choices[[1]]$message$content)) {

    # Debug log
    message("OpenRouter response was not valid JSON: ", txt)

    # Return a fallback message
    return("AI summary is temporarily unavailable. Try adjusting your filters again.")
  }

  return(result$choices[[1]]$message$content)
}


# ------------------------------
#          SERVER
# ------------------------------
server <- function(input, output, session) {

  print(Sys.getenv("OPENROUTER_API_KEY"))

  filtered_parks <- reactive({
    parks_filtered <- parks

    if (length(input$mapFilter) > 0)
      parks_filtered <- parks_filtered[parks_filtered$states %in% input$mapFilter, ]

    if (length(input$activityFilter) > 0) {
      if (input$activityLogic == "or") {
        ids <- unique(activities$park_id[activities$activity_name %in% input$activityFilter])
      } else {
        ids <- activities %>%
          filter(activity_name %in% input$activityFilter) %>%
          group_by(park_id) %>%
          summarise(n = n_distinct(activity_name)) %>%
          filter(n == length(input$activityFilter)) %>%
          pull(park_id)
      }
      parks_filtered <- parks_filtered[parks_filtered$id %in% ids, ]
    }

    if (length(input$amenityFilter) > 0) {
      if (input$amenityLogic == "or") {
        codes <- unique(amenities$parkCode[amenities$amenity_name %in% input$amenityFilter])
      } else {
        codes <- amenities %>%
          filter(amenity_name %in% input$amenityFilter) %>%
          group_by(parkCode) %>%
          summarise(n = n_distinct(amenity_name)) %>%
          filter(n == length(input$amenityFilter)) %>%
          pull(parkCode)
      }
      parks_filtered <- parks_filtered[parks_filtered$parkCode %in% codes, ]
    }

    parks_filtered
  })

  output$myMap <- renderLeaflet({
    acts <- activities %>% 
      group_by(park_id) %>% 
      summarise(activity_list = paste(sort(unique(activity_name)), collapse = ", "))

    ams <- amenities %>%
      group_by(parkCode) %>%
      summarise(amenity_list = paste(sort(unique(amenity_name)), collapse = ", "))

    dat <- filtered_parks() %>%
      left_join(acts, by = c("id" = "park_id")) %>%
      left_join(ams, by = "parkCode")

    leaflet(dat) %>%
      addTiles() %>%
      addMarkers(
        lng = as.numeric(dat$longitude),
        lat = as.numeric(dat$latitude),
        popup = paste0(
          "<b>", dat$fullName, "</b><br><br>",
          "<b>Description:</b> ", dat$description, "<br><br>",
          "<b>Activities:</b> ", dat$activity_list, "<br><br>",
          "<b>Amenities:</b> ", dat$amenity_list
        )
      )
  })

  output$activityPlot <- renderPlot({
    sel <- filtered_parks()
    df <- activities %>% 
      filter(park_id %in% sel$id) %>%
      count(activity_name, sort = TRUE) %>% 
      head(10)

    if (nrow(df) == 0) return(NULL)

    ggplot(df, aes(x = reorder(activity_name, n), y = n)) +
      geom_col(fill = "#1f77b4") +
      coord_flip() +
      labs(x = NULL, y = "Number of Parks") +
      theme_minimal(base_size = 13)
  })

  output$amenityPlot <- renderPlot({
    sel <- filtered_parks()
    df <- amenities %>%
      filter(parkCode %in% sel$parkCode) %>%
      count(amenity_name, sort = TRUE) %>%
      head(10)

    if (nrow(df) == 0) return(NULL)

    ggplot(df, aes(x = reorder(amenity_name, n), y = n)) +
      geom_col(fill = "#2ca02c") +
      coord_flip() +
      labs(x = NULL, y = "Number of Parks") +
      theme_minimal(base_size = 13)
  })

  output$llmSummary <- renderText({
    sel <- filtered_parks()
    states <- unique(sel$states)

    act <- activities %>%
      filter(park_id %in% sel$id) %>%
      count(activity_name, sort = TRUE) %>%
      head(10)

    ams <- amenities %>%
      filter(parkCode %in% sel$parkCode) %>%
      count(amenity_name, sort = TRUE) %>%
      head(10)

    generate_llm_explanation(states, act$activity_name, ams$amenity_name)
  })
}

# ------------------------------
#        RUN APP
# ------------------------------
shinyApp(ui, server)
