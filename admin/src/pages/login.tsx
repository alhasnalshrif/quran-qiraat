import { useState } from 'react';

import { Alert, Button, Card, Form, Input, Typography } from 'antd';

import * as api from '../api/client.js';

/** `/login` (02 §6): the only page available without a session. */
export function LoginPage({ onSignedIn }: { onSignedIn: (me: api.Me) => void }) {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <div style={{ display: 'grid', placeItems: 'center', minHeight: '100vh', background: '#f5f5f5' }}>
      <Card style={{ width: 380 }}>
        <Typography.Title level={4}>لوحة التحكم</Typography.Title>
        <Typography.Paragraph type="secondary">سجّل الدخول بحسابك الإداري.</Typography.Paragraph>

        {error && <Alert type="error" message={error} style={{ marginBottom: 16 }} />}

        <Form
          layout="vertical"
          onFinish={async (values: { email: string; password: string }) => {
            setBusy(true);
            setError(null);
            try {
              onSignedIn(await api.login(values.email, values.password));
            } catch (cause) {
              setError(cause instanceof Error ? cause.message : 'فشل الدخول.');
            } finally {
              setBusy(false);
            }
          }}
        >
          <Form.Item name="email" label="البريد" rules={[{ required: true, type: 'email' }]}>
            <Input autoComplete="username" dir="ltr" />
          </Form.Item>
          <Form.Item name="password" label="كلمة المرور" rules={[{ required: true }]}>
            <Input.Password autoComplete="current-password" dir="ltr" />
          </Form.Item>
          <Button type="primary" htmlType="submit" block loading={busy}>
            دخول
          </Button>
        </Form>
      </Card>
    </div>
  );
}
