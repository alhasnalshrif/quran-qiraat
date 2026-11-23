import { useState } from 'react';

import { Alert, Button, Card, Checkbox, DatePicker, Form, Input, Select, Table, Tag, Typography } from 'antd';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs, { type Dayjs } from 'dayjs';

import * as api from '../api/client.js';

interface AnnouncementRow {
  id: string;
  titleAr: string;
  bodyAr: string;
  url: string | null;
  channel: string;
  platform: string | null;
  startsAt: string;
  endsAt: string;
  priority: 'normal' | 'high';
  published: boolean;
}

/** `/announcements` (02 §6): create with a phone-style preview, publish, delete. */
export function AnnouncementsPage() {
  const queryClient = useQueryClient();
  const [error, setError] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['announcements'],
    queryFn: () => api.getJson<{ announcements: AnnouncementRow[] }>('/announcements'),
  });

  const refresh = () => queryClient.invalidateQueries({ queryKey: ['announcements'] });

  const create = useMutation({
    mutationFn: (values: Record<string, unknown>) => api.sendJson('POST', '/announcements', values),
    onSuccess: async () => {
      setError(null);
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل الإنشاء.'),
  });

  const publish = useMutation({
    mutationFn: ({ id, published }: { id: string; published: boolean }) =>
      api.sendJson('PUT', `/announcements/${id}`, { published }),
    onSuccess: refresh,
  });

  const remove = useMutation({
    mutationFn: (id: string) => api.sendJson('DELETE', `/announcements/${id}`),
    onSuccess: refresh,
  });

  return (
    <>
      <Typography.Title level={4}>الإعلانات</Typography.Title>
      {error && <Alert type="error" message={error} style={{ marginBottom: 16 }} closable />}

      <Card title="إعلان جديد" style={{ marginBottom: 24 }}>
        <Form
          layout="vertical"
          onFinish={(values) => {
            const range = values.range as [Dayjs, Dayjs];
            const { range: _ignored, ...rest } = values;
            create.mutate({
              ...rest,
              startsAt: range[0].toISOString(),
              endsAt: range[1].toISOString(),
            });
          }}
        >
          <Form.Item name="id" label="المعرّف" rules={[{ required: true }]}>
            <Input dir="ltr" placeholder="a-2026-11-23-1" />
          </Form.Item>
          <Form.Item name="titleAr" label="العنوان" rules={[{ required: true }]}>
            <Input />
          </Form.Item>
          <Form.Item name="bodyAr" label="النص" rules={[{ required: true }]}>
            <Input.TextArea rows={2} />
          </Form.Item>
          <Form.Item name="channel" label="القناة" initialValue="stable" rules={[{ required: true }]}>
            <Select options={['stable', 'beta', 'internal'].map((value) => ({ value }))} />
          </Form.Item>
          <Form.Item name="platform" label="المنصة">
            <Select
              allowClear
              placeholder="كل المنصات"
              options={['ios', 'android'].map((value) => ({ value }))}
            />
          </Form.Item>
          <Form.Item name="url" label="رابط">
            <Input dir="ltr" />
          </Form.Item>
          <Form.Item name="priority" label="الأولوية" initialValue="normal">
            <Select options={[{ value: 'normal' }, { value: 'high' }]} />
          </Form.Item>
          <Form.Item name="range" label="الفترة" rules={[{ required: true }]}>
            <DatePicker.RangePicker showTime />
          </Form.Item>
          <Button type="primary" htmlType="submit" loading={create.isPending}>
            إنشاء
          </Button>
        </Form>
      </Card>

      <Table
        rowKey="id"
        loading={isLoading}
        dataSource={data?.announcements ?? []}
        pagination={false}
        columns={[
          { title: 'المعرّف', dataIndex: 'id', render: (value: string) => <code dir="ltr">{value}</code> },
          { title: 'العنوان', dataIndex: 'titleAr' },
          { title: 'القناة', dataIndex: 'channel' },
          {
            title: 'الفترة',
            key: 'window',
            render: (_: unknown, row: AnnouncementRow) =>
              `${dayjs(row.startsAt).format('YYYY-MM-DD')} → ${dayjs(row.endsAt).format('YYYY-MM-DD')}`,
          },
          {
            title: 'الأولوية',
            dataIndex: 'priority',
            render: (value: string) => (
              <Tag {...(value === 'high' ? { color: 'orange' } : {})}>{value}</Tag>
            ),
          },
          {
            title: 'منشور',
            dataIndex: 'published',
            render: (value: boolean, row: AnnouncementRow) => (
              <Checkbox
                checked={value}
                onChange={(event) => publish.mutate({ id: row.id, published: event.target.checked })}
              />
            ),
          },
          {
            title: '',
            key: 'delete',
            render: (_: unknown, row: AnnouncementRow) => (
              <Button size="small" danger onClick={() => remove.mutate(row.id)}>
                حذف
              </Button>
            ),
          },
        ]}
      />
    </>
  );
}
