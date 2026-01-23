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
    HTTP Function che recupera i livelli delle maree dalle stazioni reali
    e calcola il livello stimato per ogni zona usando IDW (Inverse Distance Weighting).
    """
    
    # Zone di Venezia (stesse di fetch_uv_data)
    zones = [
        {"id": 1, "name": "S. Geremia - Zona 1", "lat": 45.4483, "lon": 12.3246},
        {"id": 2, "name": "S. Geremia - Zona 2", "lat": 45.4442, "lon": 12.3294},
        {"id": 3, "name": "S. Geremia - Zona 3", "lat": 45.4468, "lon": 12.3204},
        {"id": 4, "name": "S. Geremia - Zona 4", "lat": 45.4415, "lon": 12.3197},
        {"id": 5, "name": "S. Geremia - Zona 5", "lat": 45.4381, "lon": 12.3180},
        {"id": 6, "name": "S. Geremia - Zona 6", "lat": 45.4409, "lon": 12.3287},
        {"id": 7, "name": "S. Geremia - Zona 7", "lat": 45.4388, "lon": 12.3208},
        {"id": 8, "name": "Venezia Misericordia - Zona 8", "lat": 45.4469, "lon": 12.3317},
        {"id": 9, "name": "Venezia Misericordia - Zona 9", "lat": 45.4443, "lon": 12.3320},
        {"id": 10, "name": "Venezia Misericordia - Zona 10", "lat": 45.4424, "lon": 12.3366},
        {"id": 11, "name": "Venezia Misericordia - Zona 11", "lat": 45.4398, "lon": 12.3315},
        {"id": 12, "name": "Venezia Misericordia - Zona 12", "lat": 45.4379, "lon": 12.3334},
        {"id": 13, "name": "Venezia Misericordia - Zona 13", "lat": 45.4380, "lon": 12.3406},
        {"id": 14, "name": "Venezia Misericordia - Zona 14", "lat": 45.4367, "lon": 12.3479},
        {"id": 15, "name": "Punta Salute Canal Grande - Zona 15", "lat": 45.4355, "lon": 12.3459},
        {"id": 16, "name": "Punta Salute Canal Grande - Zona 16", "lat": 45.4353, "lon": 12.3359},
        {"id": 17, "name": "Punta Salute Canal Grande - Zona 17", "lat": 45.4334, "lon": 12.3312},
        {"id": 18, "name": "Punta Salute Canal Grande - Zona 18", "lat": 45.4316, "lon": 12.3281},
        {"id": 19, "name": "Punta Salute Canal Grande - Zona 19", "lat": 45.4372, "lon": 12.3249},
        {"id": 20, "name": "Punta Salute Canal Grande - Zona 20", "lat": 45.4373, "lon": 12.3217},
        {"id": 21, "name": "Punta Salute Canale Giudecca - Zona 21", "lat": 45.4295, "lon": 12.3318},
        {"id": 22, "name": "Punta Salute Canale Giudecca - Zona 22", "lat": 45.4304, "lon": 12.3233},
        {"id": 23, "name": "Punta Salute Canale Giudecca - Zona 23", "lat": 45.4260, "lon": 12.3370},
        {"id": 24, "name": "Punta Salute Canale Giudecca - Zona 24", "lat": 45.4256, "lon": 12.3235},
    ]
    
    api_url = "https://dati.venezia.it/sites/default/files/dataset/opendata/livello.json"

    try:
        # 1. Recupera dati dalle stazioni reali
        response = requests.get(api_url)
        
        if response.status_code != 200:
            print(f"API non ha risposto 200: {response.text}")
            return f"API Error: {response.status_code}", 500

        tide_data_list = response.json()
        
        if not isinstance(tide_data_list, list):
            return "Formato dati inatteso (non è una lista)", 500

        # 2. Estrai stazioni con coordinate e valori validi
        stations = []
        for item in tide_data_list:
            try:
                lat = float(item.get('latDDN', 0))
                lon = float(item.get('lonDDE', 0))
                valore_raw = item.get('valore', '')
                
                # Converti valore in metri
                altezza_m = float(valore_raw.replace(' m', '').replace(',', '.').strip())
                
                if lat != 0 and lon != 0:
                    stations.append({
                        'lat': lat,
                        'lon': lon,
                        'altezza_m': altezza_m
                    })
            except (ValueError, AttributeError):
                continue
        
        if not stations:
            return "Nessuna stazione con dati validi trovata", 500

        # 3. Calcola livello stimato per ogni zona usando IDW
        from math import sqrt
        
        def calculate_distance(lat1, lon1, lat2, lon2):
            """Calcola distanza euclidea approssimativa in gradi (sufficiente per distanze brevi)"""
            return sqrt((lat2 - lat1)**2 + (lon2 - lon1)**2)
        
        def estimate_tide_idw(zone_lat, zone_lon, stations):
            """Inverse Distance Weighting per stimare il livello marea"""
            numerator = 0.0
            denominator = 0.0
            power = 2.0  # Esponente per il peso (standard IDW)
            
            for station in stations:
                dist = calculate_distance(zone_lat, zone_lon, station['lat'], station['lon'])
                
                # Se molto vicino a una stazione, usa quel valore direttamente
                if dist < 0.0001:  # ~10 metri
                    return station['altezza_m']
                
                weight = 1.0 / (dist ** power)
                numerator += station['altezza_m'] * weight
                denominator += weight
            
            if denominator == 0:
                return None
            
            return numerator / denominator
        
        # 4. Salva dati per ogni zona
        db = firestore.client(database_id='default')
        timestamp = datetime.now().isoformat()
        saved_count = 0
        
        for zone in zones:
            estimated_tide_m = estimate_tide_idw(zone['lat'], zone['lon'], stations)
            
            if estimated_tide_m is None:
                continue
            
            data_to_save = {
                'data': timestamp,
                'altezza': estimated_tide_m,  # Mantieni in metri come i dati originali
                'zona_id': zone['id'],
            }
            
            db.collection('Maree').add(data_to_save)
            saved_count += 1
        
        return f"Successo! Salvati {saved_count} rilevamenti marea per {len(zones)} zone (basati su {len(stations)} stazioni)", 200

    except Exception as e:
        print(f"Errore critico maree: {e}")
        return f"Errore interno: {str(e)}", 500


@functions_framework.http
def fetch_uv_data(request):
    """
    Recupera i dati UV per diverse zone di Venezia (dal GeoJSON)
    e li salva nella collezione "Raggi UV".
    """
    
    # Zone di Venezia dal GeoJSON
    # Coordinate calcolate come centroidi approssimativi delle geometrie
    zones = [
        {"id": 1, "name": "S. Geremia - Zona 1", "lat": 45.4483, "lon": 12.3246},
        {"id": 2, "name": "S. Geremia - Zona 2", "lat": 45.4442, "lon": 12.3294},
        {"id": 3, "name": "S. Geremia - Zona 3", "lat": 45.4468, "lon": 12.3204},
        {"id": 4, "name": "S. Geremia - Zona 4", "lat": 45.4415, "lon": 12.3197},
        {"id": 5, "name": "S. Geremia - Zona 5", "lat": 45.4381, "lon": 12.3180},
        {"id": 6, "name": "S. Geremia - Zona 6", "lat": 45.4409, "lon": 12.3287},
        {"id": 7, "name": "S. Geremia - Zona 7", "lat": 45.4388, "lon": 12.3208},
        {"id": 8, "name": "Venezia Misericordia - Zona 8", "lat": 45.4469, "lon": 12.3317},
        {"id": 9, "name": "Venezia Misericordia - Zona 9", "lat": 45.4443, "lon": 12.3320},
        {"id": 10, "name": "Venezia Misericordia - Zona 10", "lat": 45.4424, "lon": 12.3366},
        {"id": 11, "name": "Venezia Misericordia - Zona 11", "lat": 45.4398, "lon": 12.3315},
        {"id": 12, "name": "Venezia Misericordia - Zona 12", "lat": 45.4379, "lon": 12.3334},
        {"id": 13, "name": "Venezia Misericordia - Zona 13", "lat": 45.4380, "lon": 12.3406},
        {"id": 14, "name": "Venezia Misericordia - Zona 14", "lat": 45.4367, "lon": 12.3479},
        {"id": 15, "name": "Punta Salute Canal Grande - Zona 15", "lat": 45.4355, "lon": 12.3459},
        {"id": 16, "name": "Punta Salute Canal Grande - Zona 16", "lat": 45.4353, "lon": 12.3359},
        {"id": 17, "name": "Punta Salute Canal Grande - Zona 17", "lat": 45.4334, "lon": 12.3312},
        {"id": 18, "name": "Punta Salute Canal Grande - Zona 18", "lat": 45.4316, "lon": 12.3281},
        {"id": 19, "name": "Punta Salute Canal Grande - Zona 19", "lat": 45.4372, "lon": 12.3249},
        {"id": 20, "name": "Punta Salute Canal Grande - Zona 20", "lat": 45.4373, "lon": 12.3217},
        {"id": 21, "name": "Punta Salute Canale Giudecca - Zona 21", "lat": 45.4295, "lon": 12.3318},
        {"id": 22, "name": "Punta Salute Canale Giudecca - Zona 22", "lat": 45.4304, "lon": 12.3233},
        {"id": 23, "name": "Punta Salute Canale Giudecca - Zona 23", "lat": 45.4260, "lon": 12.3370},
        {"id": 24, "name": "Punta Salute Canale Giudecca - Zona 24", "lat": 45.4256, "lon": 12.3235},
    ]
    
    db = firestore.client(database_id='default')
    timestamp = datetime.now().isoformat()
    saved_count = 0
    
    try:
        for zone in zones:
            # Usa Open-Meteo API per ottenere UV index reale
            url = f"https://api.open-meteo.com/v1/forecast?latitude={zone['lat']}&longitude={zone['lon']}&current=uv_index"
            
            response = requests.get(url)
            
            if response.status_code != 200:
                print(f"Errore API UV per {zone['name']}: {response.status_code}")
                continue
            
            data = response.json()
            
            # Estrai l'indice UV dalla risposta
            current_data = data.get('current', {})
            uv_index = current_data.get('uv_index')
            
            if uv_index is None:
                print(f"UV index non disponibile per {zone['name']}")
                continue
            
            data_to_save = {
                'data': timestamp,
                'valore': round(float(uv_index), 2),
                'zona_id': zone["id"],
            }
            
            # Salva su Firestore
            db.collection('Raggi UV').add(data_to_save)
            saved_count += 1
            
        return f"Successo! Salvati {saved_count} rilevamenti UV per {len(zones)} zone", 200
        
    except Exception as e:
        print(f"Errore critico UV: {e}")
        return f"Errore interno: {str(e)}", 500

