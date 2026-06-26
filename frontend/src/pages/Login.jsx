import { useState } from 'react';

export default function Login() {
  // State to track if we are logging in or creating a new account
  const [isRegistering, setIsRegistering] = useState(false);
  
  // State to track the form inputs
  const [role, setRole] = useState('player');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault(); // Prevents the page from refreshing on submit
    
    console.log("Form Submitted:", { isRegistering, role, username, password });
  };

  return (
    <div style={{ maxWidth: '400px', margin: '50px auto', fontFamily: 'sans-serif' }}>
      <h1>{isRegistering ? 'Join Gamba' : 'Welcome Back'}</h1>
      
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '15px' }}>
        
        {/* Role Selector Buttons */}
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

        {/* Credentials */}
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

        {/* Submit Button */}
        <button type="submit" style={{ padding: '12px', backgroundColor: '#333', color: 'white', border: 'none', cursor: 'pointer' }}>
          {isRegistering ? 'Register Account' : 'Log In'}
        </button>
      </form>

      {/* Toggle between Login and Register */}
      <p style={{ textAlign: 'center', marginTop: '20px' }}>
        {isRegistering ? "Already have an account? " : "Don't have an account? "}
        <button 
          onClick={() => setIsRegistering(!isRegistering)}
          style={{ background: 'none', border: 'none', color: '#007bff', textDecoration: 'underline', cursor: 'pointer' }}
        >
          {isRegistering ? 'Log in here' : 'Register here'}
        </button>
      </p>
    </div>
  );
}