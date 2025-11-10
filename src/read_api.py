import os
import json
import requests
import datetime
import sqlite3

parks_endpoint = "https://developer.nps.gov/api/v1/parks?limit=600" #base url
headers = {"X-Api-Key": os.getenv("NPS_API_KEY")}
#to set API key run "export NPS_API_KEY='your_api_key_here' in the terminal"
print(os.getenv("NPS_API_KEY"))
parks_response = requests.get(parks_endpoint, headers=headers)
parks_response.raise_for_status()  #raises an error if API call fails

data = parks_response.json() #set data to be the json
timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y %m %d %H %M %S") #get current time

with open(f"data/park_names.json", "w") as f:
        json.dump(data, f)

with open(f"logs/parks.log", 'a') as log_file:
        log_file.write(f'{timestamp} - Fetched park names from API')

amenities_endpoint = "https://developer.nps.gov/api/v1/amenities/parksplaces?limit=600" #base url
#to set API key run "export NPS_API_KEY='your_api_key_here' in the terminal"
amenities_response = requests.get(amenities_endpoint, headers=headers)
amenities_response.raise_for_status()  #raises an error if API call fails

a_data = amenities_response.json() #set data to be the json
timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y %m %d %H %M %S") #get current time

with open(f"data/amenities.json", "w") as g:
        json.dump(a_data, g)

with open(f"logs/amenities.log", 'a') as a_log_file:
        a_log_file.write(f'{timestamp} - Fetched amenities from API')

conn = sqlite3.connect('parks.db') #create db
cursor = conn.cursor() #create cursor object

#create parks table
cursor.execute("""
CREATE TABLE IF NOT EXISTS parks (
    id TEXT PRIMARY KEY,
    fullName TEXT,
    parkCode TEXT,
    states TEXT,
    description TEXT,
    latitude REAL,
    longitude REAL
)
""")
#create activities table
cursor.execute("""
CREATE TABLE IF NOT EXISTS activities (
    park_id TEXT,
    activity_id TEXT,
    activity_name TEXT,
    PRIMARY KEY (park_id, activity_id)
)
""")
#create amenities table
cursor.execute("""
CREATE TABLE IF NOT EXISTS amenities (
    amenity_id TEXT PRIMARY KEY,
    amenity_name TEXT
)
""")
#linking table for parks to amenities (many to many)
cursor.execute("""
CREATE TABLE IF NOT EXISTS park_amenities (
    parkCode TEXT,
    amenity_id TEXT,
    PRIMARY KEY (parkCode, amenity_id),
    FOREIGN KEY (parkCode) REFERENCES parks(parkCode),
    FOREIGN KEY (amenity_id) REFERENCES amenities(amenity_id)
)
""")

#insert data into parks table
for park in data["data"]:
    cursor.execute("""
        INSERT OR REPLACE INTO parks (id, fullName, parkCode, states, description, latitude, longitude)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (
        park.get("id"), #get each thing from the json and insert into table
        park.get("fullName"),
        park.get("parkCode"),
        park.get("states"),
        park.get("description"),
        float(park.get("latitude", 0) or 0),
        float(park.get("longitude", 0) or 0),
    ))
    park_id = park.get('id')
    activities = park.get("activities", [])  # list of dicts
    for activity in activities:
        cursor.execute("""
            INSERT OR REPLACE INTO activities (park_id, activity_id, activity_name)
            VALUES (?, ?, ?)
        """, (
            park_id,
            activity.get("id"),
            activity.get("name")
        ))

for amenities_list in a_data["data"]: #outer structure
    for amenity in amenities_list: #get the amenities and ids
        amenity_id = amenity.get("id")
        amenity_name = amenity.get("name")

        #put the data in the amenities table
        cursor.execute("""
            INSERT OR REPLACE INTO amenities (amenity_id, amenity_name)
            VALUES (?, ?)
        """, (amenity_id, amenity_name))

        #linking table to parks
        for park in amenity.get("parks", []): #get the park part of the json
            park_code = park.get("parkCode") #extract the parkCode
            cursor.execute("""
                INSERT OR REPLACE INTO park_amenities (parkCode, amenity_id)
                VALUES (?, ?) 
            """, (park_code, amenity_id)) #put in the parkCode and amenity_id

conn.commit()
conn.close()