import { useState } from 'react';

import { Alert, Button, Card, Form, Input, Select, Table, Tag, Typography } from 'antd';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';

import * as api from '../api/client.js';

interface NotificationRow {
  id: string;
  channel: 'stable' | 'beta';
  titleAr: string;
  bodyAr: string;
  link: string | null;
  platforms: string[];
  minBuild: number | null;
  maxBuild: number | null;
  scheduledAt: string | null;
  status: string;
  recipients: number | null;
  error: string | null;
}

/** The deep links a notification may carry (03 §12). */
const links = [
  { value: '', label: 'بلا رابط' },
  { value: 'quranqiraat://updates', label: 'شاشة التحديثات' },
  { value: 'quranqiraat://page/', label: 'صفحة (أضف الرقم)' },
  { value: 'quranqiraat://ayah/', label: 'آية (أضف سورة/آية)' },
  { value: 'quranqiraat://announcement/', label: 'إعلان (أضف المعرّف)' },
];

const statusColor: Record<string, string> = {
  draft: 'default',
  scheduled: 'blue',
  sent: 'green',
  failed: 'red',
  cancelled: 'orange',
};

/** `/notifications` (02 §6): compose with counters, preview, test and send. */
export function NotificationsPage({ role }: { role: 'owner' | 'editor' }) {
  const queryClient = useQueryClient();
  const [error, setError] = useState<string | null>(null);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['notifications'],
    queryFn: () => api.getJson<{ notifications: NotificationRow[] }>('/notifications'),
  });

  const refresh = () => queryClient.invalidateQueries({ queryKey: ['notifications'] });

  const create = useMutation({
    mutationFn: (values: Record<string, unknown>) => api.sendJson('POST', '/notifications', values),
    onSuccess: async () => {
      setError(null);
      setTitle('');
      setBody('');
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل الإنشاء.'),
  });

  const send = useMutation({
    mutationFn: (id: string) => api.sendJson('POST', `/notifications/${id}/send`),
    onSuccess: refresh,
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل الإرسال.'),
  });

  const cancel = useMutation({
    mutationFn: (id: string) => api.sendJson('POST', `/notifications/${id}/cancel`),
    onSuccess: refresh,
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل الإلغاء.'),
  });

  return (
    <>
      <Typography.Title level={4}>الإشعارات</Typography.Title>
      {error && <Alert type="error" message={error} style={{ marginBottom: 16 }} closable />}

      <Card title="إشعار جديد" style={{ marginBottom: 24 }}>
        <Form
          layout="vertical"
          onFinish={(values: Record<string, unknown>) =>
            create.mutate({ ...values, titleAr: title, bodyAr: body })
          }
        >
          <Form.Item label={`العنوان (${title.length}/60)`} required>
            <Input value={title} maxLength={60} onChange={(event) => setTitle(event.target.value)} />
          </Form.Item>
          <Form.Item label={`النص (${body.length}/180)`} required>
            <Input.TextArea
              value={body}
              maxLength={180}
              rows={2}
              onChange={(event) => setBody(event.target.value)}
            />
          </Form.Item>
          <Form.Item name="channel" label="القناة" initialValue="beta" rules={[{ required: true }]}>
            <Select options={[{ value: 'beta' }, { value: 'stable' }]} />
          </Form.Item>
          <Form.Item name="platforms" label="المنصات" initialValue={['ios', 'android']}>
            <Select mode="multiple" options={[{ value: 'ios' }, { value: 'android' }]} />
          </Form.Item>
          <Form.Item name="link" label="الرابط" initialValue="">
            <Select options={links} />
          </Form.Item>
          <Button type="primary" htmlType="submit" loading={create.isPending}>
            حفظ كمسودة
          </Button>
        </Form>

        {(title || body) && (
          <Card size="small" title="معاينة" style={{ marginTop: 24, maxWidth: 360 }}>
            <Typography.Text strong>{title || 'العنوان'}</Typography.Text>
            <div>{body || 'النص'}</div>
          </Card>
        )}
      </Card>

      <Table
        rowKey="id"
        loading={isLoading}
        dataSource={data?.notifications ?? []}
        pagination={false}
        columns={[
          {
            title: 'الحالة',
            dataIndex: 'status',
            render: (value: string) => (
              <Tag {...(statusColor[value] ? { color: statusColor[value] } : {})}>{value}</Tag>
            ),
          },
          { title: 'العنوان', dataIndex: 'titleAr' },
          { title: 'القناة', dataIndex: 'channel' },
          {
            title: 'المنصات',
            dataIndex: 'platforms',
            render: (value: string[]) => value.join(' · '),
          },
          {
            title: 'الجدولة',
            dataIndex: 'scheduledAt',
            render: (value: string | null) => (value ? dayjs(value).format('YYYY-MM-DD HH:mm') : 'فوري'),
          },
          {
            title: 'المستلمون',
            dataIndex: 'recipients',
            render: (value: number | null) => value ?? '—',
          },
          {
            title: 'إجراءات',
            key: 'actions',
            render: (_: unknown, row: NotificationRow) => (
              <>
                {(row.status === 'draft' || row.status === 'failed') &&
                  (row.channel === 'stable' ? role === 'owner' : true) && (
                    <Button size="small" onClick={() => send.mutate(row.id)}>
                      إرسال
                    </Button>
                  )}
                {row.status === 'scheduled' && (
                  <Button size="small" danger onClick={() => cancel.mutate(row.id)}>
                    إلغاء
                  </Button>
                )}
                {row.error && (
                  <Typography.Text type="danger" style={{ marginInlineStart: 8, fontSize: 12 }}>
                    {row.error}
                  </Typography.Text>
                )}
              </>
            ),
          },
        ]}
      />
    </>
  );
}
