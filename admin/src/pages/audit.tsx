import { Alert, Table, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import dayjs from 'dayjs';

import * as api from '../api/client.js';

interface AuditEntry {
  id: string;
  action: string;
  target: string | null;
  details: unknown;
  at: string;
  user: string | null;
}

/** `/audit` (02 §6): every write, paginated, owners only. */
export function AuditPage({ role }: { role: 'owner' | 'editor' }) {
  const [page, setPage] = useState(0);
  const limit = 50;

  const { data, isLoading } = useQuery({
    queryKey: ['audit', page],
    queryFn: () => api.getJson<{ entries: AuditEntry[]; total: number }>(`/audit?limit=${limit}&offset=${page * limit}`),
    enabled: role === 'owner',
  });

  if (role !== 'owner') {
    return <Alert type="warning" message="هذه الصفحة للمالك فقط." />;
  }

  return (
    <>
      <Typography.Title level={4}>سجل التدقيق</Typography.Title>
      <Table
        rowKey="id"
        loading={isLoading}
        dataSource={data?.entries ?? []}
        pagination={{
          current: page + 1,
          pageSize: limit,
          total: data?.total ?? 0,
          onChange: (next) => setPage(next - 1),
          showSizeChanger: false,
        }}
        columns={[
          {
            title: 'الوقت',
            dataIndex: 'at',
            render: (value: string) => dayjs(value).format('YYYY-MM-DD HH:mm'),
          },
          { title: 'المستخدم', dataIndex: 'user', render: (value: string | null) => value ?? '—' },
          { title: 'الإجراء', dataIndex: 'action', render: (value: string) => <code dir="ltr">{value}</code> },
          {
            title: 'الهدف',
            dataIndex: 'target',
            render: (value: string | null) => (value ? <span dir="ltr">{value}</span> : '—'),
          },
          {
            title: 'التفاصيل',
            dataIndex: 'details',
            render: (value: unknown) =>
              value ? <code dir="ltr" style={{ fontSize: 11 }}>{JSON.stringify(value)}</code> : '—',
          },
        ]}
      />
    </>
  );
}
