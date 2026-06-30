import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../api';

const CITIES = ['Berlin', 'Paris', 'Amsterdam', 'Madrid', 'Rome', 'Vienna', 'Prague', 'Warsaw', 'Budapest', 'Lisbon'];
const SPORTS = ['Football', 'Basketball', 'Tennis', 'Volleyball', 'Badminton'];

function getTimeSlots() {
  const slots = [];
  const now = new Date();
  now.setMinutes(0, 0, 0);
  for (let i = 1; i <= 72; i++) {
    const t = new Date(now.getTime() + i * 3600000);
    slots.push(t.toISOString().slice(0, 16));
  }
  return slots;
}

export default function OrganizerView() {
  const navigate = useNavigate();
  const slots = getTimeSlots();
  const [form, setForm] = useState({
    city: 'Berlin', address: '', sport: 'Football',
    level: 1, event_time: slots[0], capacity: 10,
  });
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const set = (field) => (e) => setForm((f) => ({ ...f, [field]: e.target.value }));

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError(''); setMessage('');
    try {
      await api.post('/api/events', {
        ...form,
        level: parseInt(form.level),
        capacity: parseInt(form.capacity),
        event_time: new Date(form.event_time).toISOString(),
      });
      setMessage('Event created!');
      setForm((f) => ({ ...f, address: '' }));
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to create event');
    }
  };

  return (
    <div style={{ maxWidth: 480, margin: '40px auto', fontFamily: 'sans-serif' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1>Create Event</h1>
        <button onClick={() => { localStorage.removeItem('gamba_token'); navigate('/'); }}
          style={{ background: 'none', border: 'none', color: '#007bff', cursor: 'pointer' }}>
          Logout
        </button>
      </div>

      {message && <div style={{ color: 'green', marginBottom: 12 }}>{message}</div>}
      {error && <div style={{ color: 'red', marginBottom: 12 }}>{error}</div>}

      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <select value={form.city} onChange={set('city')} style={{ padding: 8 }}>
          {CITIES.map((c) => <option key={c}>{c}</option>)}
        </select>
        <input placeholder="Address" value={form.address} onChange={set('address')}
          required style={{ padding: 8 }} />
        <select value={form.sport} onChange={set('sport')} style={{ padding: 8 }}>
          {SPORTS.map((s) => <option key={s}>{s}</option>)}
        </select>
        <select value={form.level} onChange={set('level')} style={{ padding: 8 }}>
          {[1, 2, 3, 4, 5].map((l) => <option key={l} value={l}>Level {l}</option>)}
        </select>
        <select value={form.event_time} onChange={set('event_time')} style={{ padding: 8 }}>
          {slots.map((s) => <option key={s} value={s}>{s.replace('T', ' ')}</option>)}
        </select>
        <select value={form.capacity} onChange={set('capacity')} style={{ padding: 8 }}>
          {Array.from({ length: 49 }, (_, i) => i + 2).map((n) =>
            <option key={n} value={n}>{n} players</option>)}
        </select>
        <button type="submit"
          style={{ padding: 12, background: '#28a745', color: 'white', border: 'none', cursor: 'pointer' }}>
          Create Event
        </button>
      </form>
    </div>
  );
}
