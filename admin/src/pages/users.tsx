import { Alert, Button, Switch, Table, Tag, Typography } from 'antd';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import * as api from '../api/client.js';

interface UserRow {
  id: string;
  email: string;
  role: 'owner' | 'editor';
  disabled: boolean;
  lastLoginAt: string | null;
}

/** `/users` (02 §6): owners list accounts and disable them. */
export function UsersPage({ role }: { role: 'owner' | 'editor' }) {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ['users'],
    queryFn: () => api.getJson<{ users: UserRow[] }>('/users'),
    enabled: role === 'owner',
  });

  const toggle = useMutation({
    mutationFn: ({ id, disabled }: { id: string; disabled: boolean }) =>
      api.sendJson('PUT', `/users/${id}`, { disabled }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['users'] }),
  });

  if (role !== 'owner') {
    return <Alert type="warning" message="هذه الصفحة للمالك فقط." />;
  }

  return (
    <>
      <Typography.Title level={4}>المستخدمون</Typography.Title>
      <Typography.Paragraph type="secondary">
        لا يوجد تسجيل ذاتي. أول مالك يُنشأ بأمر <code dir="ltr">create-owner</code>.
      </Typography.Paragraph>

      {toggle.error && (
        <Alert
          type="error"
          message={toggle.error instanceof Error ? toggle.error.message : 'فشل التحديث.'}
          style={{ marginBottom: 16 }}
        />
      )}

      <Table
        rowKey="id"
        loading={isLoading}
        dataSource={data?.users ?? []}
        pagination={false}
        columns={[
          { title: 'البريد', dataIndex: 'email', render: (value: string) => <span dir="ltr">{value}</span> },
          {
            title: 'الدور',
            dataIndex: 'role',
            render: (value: string) => (
              <Tag {...(value === 'owner' ? { color: 'gold' } : {})}>{value}</Tag>
            ),
          },
          {
            title: 'معطّل',
            dataIndex: 'disabled',
            render: (value: boolean, row: UserRow) => (
              <Switch
                checked={value}
                onChange={(checked) => toggle.mutate({ id: row.id, disabled: checked })}
              />
            ),
          },
          {
            title: 'آخر دخول',
            dataIndex: 'lastLoginAt',
            render: (value: string | null) => value ?? '—',
          },
          {
            title: '',
            key: 'hint',
            render: () => <Button size="small" disabled>إضافة editor بأمر CLI</Button>,
          },
        ]}
      />
    </>
  );
}
