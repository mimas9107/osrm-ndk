// map.js – simple GPS + OSRM routing UI for Android WebView
// Uses Leaflet (local copy under leaflet/). All network calls go to the OSRM engine on the device.

let map;
let userMarker = null;
let waypointMarkers = [];
let routeLayer = null;
let stepsDiv = null;

function initMap() {
  map = L.map('map').setView([25.0478, 121.5319], 13); // Default to Taipei
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);

  // Click to add waypoint
  map.on('click', e => {
    addWaypoint(e.latlng);
  });

  // Toolbar actions
  document.getElementById('locBtn').addEventListener('click', () => locateUser());
  document.getElementById('clearBtn').addEventListener('click', () => clearWaypoints());
  document.getElementById('routeBtn').addEventListener('click', () => planRoute());

  // Optional: show steps in a simple overlay
  stepsDiv = L.control({position: 'bottomright'});
  stepsDiv.onAdd = function(){
    const div = L.DomUtil.create('div','steps-panel');
    div.style.maxHeight='200px';
    div.style.overflowY='auto';
    div.style.background='rgba(255,255,255,0.9)';
    div.style.padding='4px';
    div.style.fontSize='12px';
    return div;
  };
  stepsDiv.addTo(map);
}

function locateUser(){
  if (!navigator.geolocation) {
    alert('此裝置不支援定位');
    return;
  }
  navigator.geolocation.getCurrentPosition(pos => {
    const latlng = [pos.coords.latitude, pos.coords.longitude];
    if (userMarker) {
      userMarker.setLatLng(latlng);
    } else {
      userMarker = L.marker(latlng,{icon:L.icon({iconUrl:'https://maps.gstatic.com/mapfiles/ms2/micons/blue.png',iconSize:[32,32],iconAnchor:[16,32]})}).addTo(map);
    }
    map.setView(latlng, 15);
  }, err => {
    alert('定位失敗: ' + err.message);
  });
}

function addWaypoint(latlng){
  const idx = waypointMarkers.length + 1;
  const marker = L.marker(latlng,{draggable:true}).addTo(map);
  marker.bindPopup('Waypoint ' + idx).openPopup();
  marker.on('dragend',()=>{ /* keep coordinates updated automatically */ });
  waypointMarkers.push(marker);
}

function clearWaypoints(){
  waypointMarkers.forEach(m=>map.removeLayer(m));
  waypointMarkers = [];
  if (routeLayer){ map.removeLayer(routeLayer); routeLayer=null; }
  stepsDiv.getContainer().innerHTML='';
}

function planRoute(){
  if (waypointMarkers.length < 2) {
    alert('請至少加入 2 個點位');
    return;
  }
  const coords = waypointMarkers.map(m=>{
    const ll = m.getLatLng();
    return `${ll.lng},${ll.lat}`; // OSRM expects lon,lat
  }).join(';');
  const url = `http://127.0.0.1:5747/trip/v1/motorcycle/${coords}?source=first&destination=any&roundtrip=false&steps=true&geometries=geojson&overview=full`;
  fetch(url).then(r=>r.json()).then(data=>{
    if (data.code !== 'Ok') { alert('OSRM 錯誤: '+data.message); return; }
    const trip = data.trips[0];
    // draw route
    if (routeLayer){ map.removeLayer(routeLayer); }
    routeLayer = L.geoJSON(trip.geometry, {style:{color:'#ff6600',weight:5}}).addTo(map);
    // update waypoints order according to trips_index
    const order = data.waypoints.map(w=>w.trips_index);
    const orderedMarkers = order.map(i=>waypointMarkers[i]);
    // re-number markers
    orderedMarkers.forEach((m,i)=>{ m.setPopupContent('Waypoint '+(i+1)); });
    // show steps
    const stepsHtml = [];
    trip.legs.forEach((leg,li)=>{
      stepsHtml.push(`<b>段 ${li+1}：</b>距離 ${(leg.distance/1000).toFixed(2)} km, 時間 ${(leg.duration/60).toFixed(1)} min`);
      leg.steps.forEach(st=>{
        const instr = st.maneuver.instruction || `${st.maneuver.type} ${st.maneuver.modifier||''}`;
        stepsHtml.push(`${instr} (${(st.distance).toFixed(0)} m)`);
      });
    });
    stepsDiv.getContainer().innerHTML = stepsHtml.join('<br/>');
    map.fitBounds(routeLayer.getBounds());
  }).catch(err=>{
    alert('呼叫 OSRM 失敗: '+err);
  });
}

// Init after DOM ready
document.addEventListener('DOMContentLoaded', initMap);
