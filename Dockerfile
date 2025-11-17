# Use an official Python image as the base
FROM python:3.11

# Set the working directory in the container
WORKDIR /app
#make data and logs directories
RUN mkdir -p data logs

#Copy everything into the container
COPY src/ /app/src/
COPY requirements.txt /app/

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Run the app
CMD ["python", "src/read_api.py"]
