import functions_framework
import firebase_admin
from firebase_admin import firestore
import requests
import os
from datetime import datetime

# Inizializza Firebase
if not firebase_admin._apps:
    firebase_admin.initialize_app()

# Modifica qui: Usa @functions_framework.http per combaciare con --trigger-http
@functions_framework.http
def fetch_venice_weather(request):
    """
    HTTP Function che recupera il meteo e lo salva su Firestore.
    """
    
    # 1. Recupera API Key
    GOOGLE_MAPS_API_KEY = os.environ.get('GOOGLE_MAPS_API_KEY')
    if not GOOGLE_MAPS_API_KEY:
        return "Errore: API Key mancante", 500
    
    VENICE_LAT = 45.44
    VENICE_LON = 12.33
    
    # NOTA: L'URL che avevi (weather.googleapis.com) è per servizi Enterprise interni.
    # Qui uso WeatherAPI.com come esempio funzionante (perché WeatherAPI è partner Google Cloud).
    # Assicurati che l'API Key nel .env sia valida per il servizio che stai chiamando.
    # Se stai usando WeatherAPI.com:
    # api_url = f"http://api.weatherapi.com/v1/current.json?key={GOOGLE_MAPS_API_KEY}&q={VENICE_LAT},{VENICE_LON}"
    
    # Se vuoi mantenere il tuo URL (assicurati che sia corretto):
    api_url = f"https://weather.googleapis.com/v1/currentConditions:lookup?key={GOOGLE_MAPS_API_KEY}&location.latitude={VENICE_LAT}&location.longitude={VENICE_LON}"

    try:
        response = requests.get(api_url)
        # response.raise_for_status() # Scommenta se vuoi fermarti sugli errori HTTP
        
        # Gestione difensiva del JSON
        if response.status_code == 200:
            weather_data = response.json()
             # Adatta questo parsing in base alla risposta reale della TUA API
            temperature_celsius = weather_data.get('temperature', {}).get('degrees', 0) 
        else:
            print(f"API non ha risposto 200: {response.text}")
            return f"API Error: {response.status_code}", 500

        # Prepara i dati
        timestamp = datetime.now().isoformat()
        data_to_save = {
            'data': timestamp,
            'valore': temperature_celsius,
        }

        # Salva su Firestore
        db = firestore.client(database_id='default')
        doc_ref = db.collection('Temperatura').add(data_to_save)
        
        return f"Successo! ID: {doc_ref[1].id} - Temp: {temperature_celsius}", 200

    except Exception as e:
        print(f"Errore critico alvio: {e}")
        return f"Errore interno: {str(e)}", 500

@functions_framework.http
def fetch_venice_air_quality(request):
    """
    Recupera la qualità dell'aria (AQI) da Google Air Quality API
    e la salva nella collezione "Qualita dell'aria".
    """
    
    # Recupera l'API Key dalle variabili d'ambiente
    GOOGLE_MAPS_API_KEY = os.environ.get('GOOGLE_MAPS_API_KEY')
    if not GOOGLE_MAPS_API_KEY:
        return "Errore: GOOGLE_MAPS_API_KEY mancante", 500
        
    VENICE_LAT = 45.44
    VENICE_LON = 12.33
    
    # Endpoint Google Air Quality
    url = f"https://airquality.googleapis.com/v1/currentConditions:lookup?key={GOOGLE_MAPS_API_KEY}"
    
    payload = {
        "location": {
            "latitude": VENICE_LAT,
            "longitude": VENICE_LON
        },
        # Chiediamo sia l'indice universale (UAQI) che quello locale (se disponibile)
        "extraComputations": ["LOCAL_AQI"] 
    }

    try:
        # È una richiesta POST
        response = requests.post(url, json=payload)
        
        if response.status_code != 200:
            return f"Errore API Air Quality: {response.status_code} - {response.text}", 500

        data = response.json()
        
        # Estrazione dati (struttura complessa, prendiamo il primo indice disponibile)
        indexes = data.get('indexes', [])
        if not indexes:
            return "Nessun indice AQI trovato nella risposta", 500
            
        # Cerchiamo l'indice universale "Universal AQI" o prendiamo il primo
        aqi_data = indexes[0]
        for idx in indexes:
            if idx.get('code') == 'uaqi':
                aqi_data = idx
                break
        
        aqi_value = aqi_data.get('aqi')
        category = aqi_data.get('category') # Es: "Good", "Moderate"
        
        timestamp = datetime.now().isoformat()
        
        data_to_save = {
            'data': timestamp,
            'valore': aqi_value,
            'categoria': category,
        }

        # Salvataggio su Firestore
        db = firestore.client(database_id='default')
        # Nota: "Qualita dell'aria" con gli spazi è accettabile come nome collection
        doc_ref = db.collection("Qualita dell'aria").add(data_to_save)
        
        return f"Successo! AQI: {aqi_value} ({category}) salvato con ID: {doc_ref[1].id}", 200
        
    except Exception as e:
        print(f"Errore critico AQI: {e}")
        return f"Errore interno: {str(e)}", 500


@functions_framework.http
def fetch_tide_levels(request):
    """
    HTTP Function che recupera i livelli delle maree e li salva su Firestore.
    """
    
    VENICE_LAT = 45.44
    VENICE_LON = 12.33
    
    # Se vuoi mantenere il tuo URL (assicurati che sia corretto):
    api_url = "https://dati.venezia.it/sites/default/files/dataset/opendata/livello.json"

    try:
        response = requests.get(api_url)
        # response.raise_for_status() # Scommenta se vuoi fermarti sugli errori HTTP
        
        # Gestione difensiva del JSON
        if response.status_code != 200:
            print(f"API non ha risposto 200: {response.text}")
            return f"API Error: {response.status_code}", 500

        tide_data_list = response.json()
        
        if not isinstance(tide_data_list, list):
             return "Formato dati inatteso (non è una lista)", 500

        db = firestore.client(database_id='default')
        saved_count = 0

        for item in tide_data_list:
            stazione = item.get('stazione')
            data_misurazione = item.get('data')
            valore_raw = item.get('valore')

            # Verifica che i campi essenziali esistano
            if stazione and data_misurazione and valore_raw:
                try:
                    # Rimuove " m" e converte in float
                    altezza = float(valore_raw.replace(' m', '').strip())
                    
                    data_to_save = {
                        'zona': stazione,
                        'data': data_misurazione,
                        'altezza': altezza,
                    }

                    # Salva su Firestore
                    db.collection('Maree').add(data_to_save)
                    saved_count += 1
                except ValueError:
                    print(f"Errore conversione valore per {stazione}: {valore_raw}")
                    continue

        return f"Successo! Salvati {saved_count} rilevamenti marea.", 200

    except Exception as e:
        print(f"Errore critico alvio: {e}")
        return f"Errore interno: {str(e)}", 500

