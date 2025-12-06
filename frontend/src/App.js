import React, { useState, useEffect } from "react";
import "./App.css";

// API URL for backend
// In local dev, leave REACT_APP_API_URL undefined and rely on the CRA proxy
// (see `proxy` in package.json) so we can call relative URLs without CORS.
// In production you can set REACT_APP_API_URL to an absolute URL.
const API_URL = process.env.REACT_APP_API_URL || "";

function App() {
  const [buoys, setBuoys] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);

  const fetchBuoys = async () => {
    try {
      setLoading(true);

      // Call backend `/readings-latest` endpoint and ask for the single latest row.
      const response = await fetch(`${API_URL}/readings-latest?limit=1`);
      const data = await response.json();

      const rows = Array.isArray(data.rows) ? data.rows : [];
      const latest = rows[0];

      const mappedBuoys = latest
        ? (() => {
            const sensorData = latest.sensor_data || {};
            const numericReading = Number(sensorData.reading);

            const oilDetected =
              latest.oil_detected === true ||
              sensorData.oil_detected === true ||
              (!Number.isNaN(numericReading) && numericReading >= 1);

            return [
              {
                buoy_id: latest.buoy_id,
                latitude: Number(latest.latitude) || 0,
                longitude: Number(latest.longitude) || 0,
                oil_detected: oilDetected,
                // Optional: expose the raw reading if you want to display it
                reading: Number.isNaN(numericReading) ? null : numericReading,
                last_updated: latest.created_at || latest.timestamp,
              },
            ];
          })()
        : [];

      setBuoys(mappedBuoys);
      setLastUpdated(new Date());
      setError(null);
    } catch (err) {
      setError("Unable to connect to server. Using demo data.");
      // Demo data for testing without backend
      setBuoys([
        {
          buoy_id: "B001",
          latitude: 1.2897,
          longitude: 103.8501,
          oil_detected: true,
          last_updated: new Date().toISOString(),
        },
        {
          buoy_id: "B002",
          latitude: 1.3521,
          longitude: 103.8198,
          oil_detected: false,
          last_updated: new Date().toISOString(),
        },
        {
          buoy_id: "B003",
          latitude: 1.2904,
          longitude: 103.852,
          oil_detected: true,
          last_updated: new Date().toISOString(),
        },
        {
          buoy_id: "B004",
          latitude: 1.3,
          longitude: 103.75,
          oil_detected: false,
          last_updated: new Date().toISOString(),
        },
        {
          buoy_id: "B005",
          latitude: 1.25,
          longitude: 103.9,
          oil_detected: false,
          last_updated: new Date().toISOString(),
        },
      ]);
      setLastUpdated(new Date());
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBuoys();
    // Refresh every 30 seconds
    const interval = setInterval(fetchBuoys, 30000);
    return () => clearInterval(interval);
  }, []);

  const oilDetectedCount = buoys.filter((b) => b.oil_detected).length;
  const safeCount = buoys.filter((b) => !b.oil_detected).length;

  return (
    <div className="app">
      {/* Background Effects */}
      <div className="bg-gradient" />
      <div className="bg-grid" />

      {/* Header */}
      <header className="header">
        <div className="logo">
          <span className="logo-icon">🛢️</span>
          <h1>Oil Detection</h1>
        </div>
        <div className="header-info">
          {lastUpdated && (
            <span className="last-updated">
              Last updated: {lastUpdated.toLocaleTimeString()}
            </span>
          )}
          <button
            className="refresh-btn"
            onClick={fetchBuoys}
            disabled={loading}
          >
            {loading ? "⟳ Refreshing..." : "⟳ Refresh"}
          </button>
        </div>
      </header>

      {/* Status Summary */}
      <div className="summary">
        <div className="summary-card total">
          <span className="summary-number">{buoys.length}</span>
          <span className="summary-label">Total Buoys</span>
        </div>
        <div className="summary-card danger">
          <span className="summary-number">{oilDetectedCount}</span>
          <span className="summary-label">Oil Detected</span>
          <div className="pulse-ring" />
        </div>
        <div className="summary-card safe">
          <span className="summary-number">{safeCount}</span>
          <span className="summary-label">All Clear</span>
        </div>
      </div>

      {/* Error Banner */}
      {error && <div className="error-banner">⚠️ {error}</div>}

      {/* Buoy Grid */}
      <main className="buoy-grid">
        {buoys.map((buoy) => (
          <div
            key={buoy.buoy_id}
            className={`buoy-card ${buoy.oil_detected ? "danger" : "safe"}`}
          >
            <div className="buoy-header">
              <span className="buoy-id">{buoy.buoy_id}</span>
              <span
                className={`status-badge ${
                  buoy.oil_detected ? "danger" : "safe"
                }`}
              >
                {buoy.oil_detected ? "🔴 OIL DETECTED" : "🟢 CLEAR"}
              </span>
            </div>

            <div className="buoy-status">
              {buoy.oil_detected ? (
                <div className="status-icon danger">
                  <span className="icon">⚠️</span>
                  <span className="status-text">Oil Spill Detected</span>
                </div>
              ) : (
                <div className="status-icon safe">
                  <span className="icon">✓</span>
                  <span className="status-text">No Oil Detected</span>
                </div>
              )}
            </div>

            <div className="buoy-details">
              <div className="detail">
                <span className="detail-label">Latitude</span>
                <span className="detail-value">
                  {buoy.latitude.toFixed(4)}°
                </span>
              </div>
              <div className="detail">
                <span className="detail-label">Longitude</span>
                <span className="detail-value">
                  {buoy.longitude.toFixed(4)}°
                </span>
              </div>
            </div>

            <div className="buoy-footer">
              <span className="timestamp">
                📡{" "}
                {buoy.last_updated
                  ? new Date(buoy.last_updated).toLocaleString()
                  : "Just now"}
              </span>
            </div>

            {buoy.oil_detected && <div className="danger-pulse" />}
          </div>
        ))}
      </main>

      {/* Footer */}
      <footer className="footer">
        <p>Oil Detection Monitoring System • Real-time Sensor Data</p>
      </footer>
    </div>
  );
}

export default App;
