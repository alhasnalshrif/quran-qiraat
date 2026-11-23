import { useEffect, useState } from 'react';

import { ConfigProvider, Layout, Menu, Spin, Typography } from 'antd';
import arEG from 'antd/locale/ar_EG';
import {
  AppstoreOutlined,
  AuditOutlined,
  BellOutlined,
  CloudServerOutlined,
  DashboardOutlined,
  NotificationOutlined,
  SettingOutlined,
  TeamOutlined,
} from '@ant-design/icons';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Link, Route, Routes, useLocation } from 'react-router-dom';

import * as api from './api/client.js';
import { AnnouncementsPage } from './pages/announcements.js';
import { AuditPage } from './pages/audit.js';
import { ConfigPage } from './pages/config.js';
import { DashboardPage } from './pages/dashboard.js';
import { LoginPage } from './pages/login.js';
import { NotificationsPage } from './pages/notifications.js';
import { PackPage } from './pages/pack.js';
import { PacksPage } from './pages/packs.js';
import { PlatformsPage } from './pages/platforms.js';
import { UsersPage } from './pages/users.js';

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false } },
});

const { Header, Sider, Content } = Layout;

/**
 * The dashboard shell (02 §6): Arabic RTL throughout, a side menu, and a login
 * gate in front of every page.
 */
export function App() {
  return (
    <ConfigProvider direction="rtl" locale={arEG} theme={{ token: { fontFamily: 'system-ui, sans-serif' } }}>
      <QueryClientProvider client={queryClient}>
        <Shell />
      </QueryClientProvider>
    </ConfigProvider>
  );
}

function Shell() {
  const [session, setSession] = useState<api.Me | null | undefined>(undefined);
  const location = useLocation();

  useEffect(() => {
    api
      .me()
      .then(setSession)
      .catch(() => setSession(null));
  }, []);

  if (session === undefined) {
    return (
      <div style={{ display: 'grid', placeItems: 'center', minHeight: '100vh' }}>
        <Spin size="large" />
      </div>
    );
  }

  if (session === null || location.pathname === '/login') {
    return (
      <Routes>
        <Route path="*" element={<LoginPage onSignedIn={setSession} />} />
      </Routes>
    );
  }

  const isOwner = session.user.role === 'owner';
  const items = [
    { key: '/', icon: <DashboardOutlined />, label: <Link to="/">الرئيسية</Link> },
    { key: '/packs', icon: <AppstoreOutlined />, label: <Link to="/packs">الحزم</Link> },
    { key: '/platforms', icon: <CloudServerOutlined />, label: <Link to="/platforms">النسخ والمنصات</Link> },
    { key: '/announcements', icon: <NotificationOutlined />, label: <Link to="/announcements">الإعلانات</Link> },
    { key: '/notifications', icon: <BellOutlined />, label: <Link to="/notifications">الإشعارات</Link> },
    ...(isOwner
      ? [
          { key: '/config', icon: <SettingOutlined />, label: <Link to="/config">الإعدادات البعيدة</Link> },
          { key: '/users', icon: <TeamOutlined />, label: <Link to="/users">المستخدمون</Link> },
          { key: '/audit', icon: <AuditOutlined />, label: <Link to="/audit">سجل التدقيق</Link> },
        ]
      : []),
  ];

  const selected = items.find((item) => item.key !== '/' && location.pathname.startsWith(item.key))?.key ?? '/';

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider theme="light" width={232} breakpoint="lg" collapsedWidth={0}>
        <div style={{ padding: 20 }}>
          <Typography.Title level={4} style={{ margin: 0 }}>
            لوحة التحكم
          </Typography.Title>
          <Typography.Text type="secondary">{session.user.email}</Typography.Text>
        </div>
        <Menu mode="inline" selectedKeys={[selected]} items={items} />
      </Sider>
      <Layout>
        <Header style={{ background: '#fff', display: 'flex', justifyContent: 'flex-start', paddingInline: 24 }}>
          <Typography.Link
            onClick={async () => {
              await api.logout();
              setSession(null);
            }}
          >
            خروج
          </Typography.Link>
        </Header>
        <Content style={{ padding: 24 }}>
          <Routes>
            <Route path="/" element={<DashboardPage />} />
            <Route path="/packs" element={<PacksPage role={session.user.role} />} />
            <Route path="/packs/:packId" element={<PackPage role={session.user.role} />} />
            <Route path="/platforms" element={<PlatformsPage role={session.user.role} />} />
            <Route path="/config" element={<ConfigPage role={session.user.role} />} />
            <Route path="/announcements" element={<AnnouncementsPage />} />
            <Route path="/notifications" element={<NotificationsPage role={session.user.role} />} />
            <Route path="/users" element={<UsersPage role={session.user.role} />} />
            <Route path="/audit" element={<AuditPage role={session.user.role} />} />
          </Routes>
        </Content>
      </Layout>
    </Layout>
  );
}
