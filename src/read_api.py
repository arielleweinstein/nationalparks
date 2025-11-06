import os
import json
import requests
import datetime
import sqlite3

endpoint = "https://developer.nps.gov/api/v1/parks?limit=600" #base url
headers = {"X-Api-Key": os.getenv("NPS_API_KEY")}
#to set API key run "export NPS_API_KEY='your_api_key_here' in the terminal"
print(os.getenv("NPS_API_KEY"))
response = requests.get(endpoint, headers=headers)
response.raise_for_status()  #raises an error if API call fails

data = response.json() #set data to be the json
timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y %m %d %H %M %S") #get current time

with open(f"data/park_names.json", "w") as f:
        json.dump(data, f)

with open(f"logs/parks.log", 'a') as log_file:
        log_file.write(f'{timestamp} - Fetched park names from API')

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

conn.commit()
conn.close()