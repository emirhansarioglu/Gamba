import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Login from './pages/Login';
import OrganizerView from './pages/OrganizerView';
import PlayerView from './pages/PlayerView';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Login />} />
        <Route path="/player" element={<PlayerView />} />
        <Route path="/organizer" element={<OrganizerView />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
