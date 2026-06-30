import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../api';

const CITIES = ['', 'Berlin', 'Paris', 'Amsterdam', 'Madrid', 'Rome', 'Vienna', 'Prague', 'Warsaw', 'Budapest', 'Lisbon'];
const SPORTS = ['', 'Football', 'Basketball', 'Tennis', 'Volleyball', 'Badminton'];

function todayPlusDays(n) {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
}

export default function PlayerView() {
  const navigate = useNavigate();
  const [city, setCity] = useState('');
  const [sport, setSport] = useState('');
  const [day, setDay] = useState(todayPlusDays(0));
  const [events, setEvents] = useState([]);
  const [error, setError] = useState('');

  useEffect(() => { fetchEvents(); }, [city, sport, day]);

  const fetchEvents = async () => {
    setError('');
    try {
      const params = { day };
      if (city) params.city = city;
      if (sport) params.sport = sport;
      const res = await api.get('/api/events', { params });
      setEvents(res.data);
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to load events');
    }
  };

  const join = async (id) => {
    try {
      const res = await api.post(`/api/events/${id}/join`);
      setEvents((prev) =>
        prev.map((e) => e.id === id ? { ...e, joined_count: res.data.joined_count } : e)
      );
    } catch (err) {
      alert(err.response?.data?.detail || 'Could not join');
    }
  };

  const days = [todayPlusDays(0), todayPlusDays(1), todayPlusDays(2)];

  return (
    <div style={{ maxWidth: 640, margin: '40px auto', fontFamily: 'sans-serif' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1>Find Events</h1>
        <button onClick={() => { localStorage.removeItem('gamba_token'); navigate('/'); }}
          style={{ background: 'none', border: 'none', color: '#007bff', cursor: 'pointer' }}>
          Logout
        </button>
      </div>

      <div style={{ display: 'flex', gap: 8, marginBottom: 20 }}>
        <select value={city} onChange={(e) => setCity(e.target.value)} style={{ padding: 8, flex: 1 }}>
          {CITIES.map((c) => <option key={c} value={c}>{c || 'All cities'}</option>)}
        </select>
        <select value={sport} onChange={(e) => setSport(e.target.value)} style={{ padding: 8, flex: 1 }}>
          {SPORTS.map((s) => <option key={s} value={s}>{s || 'All sports'}</option>)}
        </select>
        <select value={day} onChange={(e) => setDay(e.target.value)} style={{ padding: 8, flex: 1 }}>
          {days.map((d, i) => <option key={d} value={d}>{['Today', 'Tomorrow', 'Day after'][i]}</option>)}
        </select>
      </div>

      {error && <div style={{ color: 'red', marginBottom: 12 }}>{error}</div>}
      {events.length === 0 && <p style={{ color: '#666' }}>No events found.</p>}

      {events.map((e) => {
        const spots = e.capacity - e.joined_count;
        const full = spots <= 0;
        return (
          <div key={e.id} style={{
            border: '1px solid #ddd', borderRadius: 6, padding: 16, marginBottom: 12,
            display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          }}>
            <div>
              <strong>{e.sport}</strong> · Level {e.level} · {e.city}
              <br /><small>{e.address}</small>
              <br /><small>{new Date(e.event_time).toLocaleString()}</small>
              <br /><small style={{ color: full ? 'red' : 'green' }}>
                {full ? 'Full' : `${spots} spot${spots !== 1 ? 's' : ''} left`}
              </small>
            </div>
            <button onClick={() => join(e.id)} disabled={full} style={{
              padding: '8px 16px', background: full ? '#ccc' : '#007bff',
              color: 'white', border: 'none', cursor: full ? 'default' : 'pointer', borderRadius: 4,
            }}>
              {full ? 'Full' : 'Join'}
            </button>
          </div>
        );
      })}
    </div>
  );
}
