FROM python:3.12-slim
WORKDIR /app
COPY burn_master.py .
RUN useradd --system --no-create-home burn
USER burn
ENV PORT=47290 PYTHONUNBUFFERED=1
EXPOSE 47290
HEALTHCHECK --interval=30s --timeout=3s CMD python3 -c "import urllib.request,os; urllib.request.urlopen('http://127.0.0.1:%s/healthz' % os.environ.get('PORT','47290'), timeout=2)"
CMD ["python3", "burn_master.py"]
