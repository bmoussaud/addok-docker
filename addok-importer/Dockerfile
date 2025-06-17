
FROM python:3.10

# Install addok and dependencies
RUN pip install cython addok==1.0.3 addok-fr==1.0.1 addok-france==1.1.3 addok-sqlite-store==1.0.1 fastapi uvicorn

# Copy config and API
COPY addok.conf /etc/addok/
COPY api.py /app/api.py

ENV ADDOK_CONFIG_MODULE=/etc/addok/addok.conf
ENV REDIS_HOST=redis
ENV REDIS_PORT=6379
ENV REDIS_DB_INDEXES=0
ENV SQLITE_DB_PATH=/data/addok.db

WORKDIR /app
VOLUME ["/data"]

EXPOSE 8000

CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000"]
