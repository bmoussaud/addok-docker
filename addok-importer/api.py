from fastapi import FastAPI
from fastapi.responses import JSONResponse
import subprocess
import os
import time

app = FastAPI()

@app.get("/ping")
def ping():
    return {"message": "pong"}

@app.post("/upload")
def upload():
    # Run the first shell command: addok batch /daily/gtm.json
    try:
        batch_result = subprocess.run([
            "addok", "batch", "/daily/gtm.json"
        ], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        return JSONResponse(status_code=500, content={"error": f"Batch failed: {e.stderr}"})

    # Wait 5 seconds to ensure the batch processing is complete
    time.sleep(5)

    # Run the second shell command: addok ngrams
    try:
        ngrams_result = subprocess.run([
            "addok", "ngrams"
        ], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        return JSONResponse(status_code=500, content={"error": f"Ngrams failed: {e.stderr}"})

    # Wait 5 seconds to ensure the batch processing is complete
    time.sleep(5)
    return {
        "batch_output": batch_result.stdout,
        "wait_time": 10,  # Total wait time for both commands
        "ngrams_output": ngrams_result.stdout,
        "message": "Batch and ngrams processing completed successfully."
    }
