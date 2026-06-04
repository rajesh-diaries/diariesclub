import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider, useAuth } from './state/auth'
import { ToastHost, Spinner } from './components/ui'
import { ActorProvider } from './components/Actor'
import { BottomNav } from './components/Shell'
import { LoginScreen } from './screens/LoginScreen'
import { HomeScreen } from './screens/HomeScreen'
import { CheckInScreen } from './screens/CheckInScreen'
import { LiveSessionsScreen } from './screens/LiveSessionsScreen'
import { KitchenScreen } from './screens/KitchenScreen'
import { HealthyBitesScreen } from './screens/HealthyBitesScreen'
import { PendingPaymentsScreen } from './screens/PendingPaymentsScreen'
import { ScanScreen } from './screens/ScanScreen'
import { MenuScreen } from './screens/MenuScreen'
import { WorkshopsScreen } from './screens/WorkshopsScreen'
import { RewardsScreen } from './screens/RewardsScreen'
import { MoreScreen } from './screens/MoreScreen'
import { WalkInScreen } from './screens/WalkInScreen'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 1, refetchOnWindowFocus: true, staleTime: 5_000 },
  },
})

function Gate() {
  const { session, loading, deviceError } = useAuth()

  if (loading) {
    return (
      <div className="flex min-h-full items-center justify-center text-primary">
        <Spinner size={32} />
      </div>
    )
  }

  if (!session || deviceError) return <LoginScreen />

  return (
    <ActorProvider>
      <div className="relative flex min-h-full flex-col">
        <Routes>
          <Route path="/" element={<HomeScreen />} />
          <Route path="/checkin" element={<CheckInScreen />} />
          <Route path="/live" element={<LiveSessionsScreen />} />
          <Route path="/kitchen" element={<KitchenScreen />} />
          <Route path="/bites" element={<HealthyBitesScreen />} />
          <Route path="/pay" element={<PendingPaymentsScreen />} />
          <Route path="/scan" element={<ScanScreen />} />
          <Route path="/walkin" element={<WalkInScreen />} />
          <Route path="/menu" element={<MenuScreen />} />
          <Route path="/workshops" element={<WorkshopsScreen />} />
          <Route path="/rewards" element={<RewardsScreen />} />
          <Route path="/more" element={<MoreScreen />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
        <BottomNav />
      </div>
    </ActorProvider>
  )
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <AuthProvider>
          <ToastHost>
            <Gate />
          </ToastHost>
        </AuthProvider>
      </BrowserRouter>
    </QueryClientProvider>
  )
}
