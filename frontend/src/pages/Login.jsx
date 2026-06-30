import { useState } from 'react';
import axios from 'axios';
import { useNavigate } from 'react-router-dom';

export default function Login() {
  const [isRegistering, setIsRegistering] = useState(false);
  const [role, setRole] = useState('player');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setMessage('');
    
    try {
      if (isRegistering) {
        // --- REGISTRATION LOGIC ---
        await axios.post(`${import.meta.env.VITE_API_URL}/api/auth/register`, {
          username: username,
          password: password,
          role: role
        });
        
        setMessage("Account created! Please log in.");
        setIsRegistering(false); // Automatically switch them to the login view
        setPassword(''); // Clear the password field for safety
        
      } else {
        // --- LOGIN LOGIC ---
        const response = await axios.post(`${import.meta.env.VITE_API_URL}/api/auth/login`, {
          username: username,
          password: password
        });
        
        const { access_token, role: userRole } = response.data;
        
        localStorage.setItem('gamba_token', access_token);
        
        // Route them to their specific dashboard based on their role
        if (userRole === 'organizer') {
          navigate('/organizer');
        } else {
          navigate('/player');
        }
      }
    } catch (err) {
      if (err.response && err.response.data) {
        setError(err.response.data.detail);
      } else {
        setError("Cannot connect to server. Is FastAPI running?");
      }
    }
  };

  return (
    <div style={{ maxWidth: '400px', margin: '50px auto', fontFamily: 'sans-serif' }}>
      <h1>{isRegistering ? 'Join Gamba' : 'Welcome Back'}</h1>
      
      {/* Show Error or Success Messages */}
      {error && <div style={{ color: 'red', marginBottom: '10px' }}>{error}</div>}
      {message && <div style={{ color: 'green', marginBottom: '10px' }}>{message}</div>}
      
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '15px' }}>
        
        {isRegistering && (
          <div style={{ display: 'flex', gap: '10px' }}>
            <button 
              type="button"
              onClick={() => setRole('player')}
              style={{ flex: 1, backgroundColor: role === 'player' ? '#007bff' : '#ccc', color: 'white', padding: '10px', border: 'none', cursor: 'pointer' }}
            >
              Player
            </button>
            <button 
              type="button"
              onClick={() => setRole('organizer')}
              style={{ flex: 1, backgroundColor: role === 'organizer' ? '#28a745' : '#ccc', color: 'white', padding: '10px', border: 'none', cursor: 'pointer' }}
            >
              Organizer
            </button>
          </div>
        )}

        <input 
          type="text" 
          placeholder="Username" 
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          required
          style={{ padding: '10px' }}
        />
        <input 
          type="password" 
          placeholder="Password" 
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          style={{ padding: '10px' }}
        />

        <button type="submit" style={{ padding: '12px', backgroundColor: '#333', color: 'white', border: 'none', cursor: 'pointer' }}>
          {isRegistering ? 'Register Account' : 'Log In'}
        </button>
      </form>

      <p style={{ textAlign: 'center', marginTop: '20px' }}>
        {isRegistering ? "Already have an account? " : "Don't have an account? "}
        <button 
          onClick={() => {
            setIsRegistering(!isRegistering);
            setError('');
            setMessage('');
          }}
          style={{ background: 'none', border: 'none', color: '#007bff', textDecoration: 'underline', cursor: 'pointer' }}
        >
          {isRegistering ? 'Log in here' : 'Register here'}
        </button>
      </p>
    </div>
  );
}