import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Login from './pages/Login';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        {/* The default root URL will render the Login screen */}
        <Route path="/" element={<Login />} />
        
        {/* We will build these two pages later! */}
        {/* <Route path="/player" element={<PlayerView />} /> */}
        {/* <Route path="/organizer" element={<OrganizerView />} /> */}
      </Routes>
    </BrowserRouter>
  );
}

export default App;