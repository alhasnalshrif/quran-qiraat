import { useState } from 'react';

import { Alert, Button, Form, Input, Select, Table, Typography } from 'antd';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import * as api from '../api/client.js';

interface ConfigRow {
  key: string;
  channel: 'stable' | 'beta' | 'internal';
  platform: 'ios' | 'android' | null;
  minBuild: number | null;
  maxBuild: number | null;
  value: unknown;
}

/** Approved keys, from 01 §4. The server rejects anything else. */
const keys = [
  { value: 'updates.checkIntervalHours', kind: 'int', hint: 'عدد صحيح 1–168' },
  { value: 'updates.wifiOnlyDefault', kind: 'bool', hint: 'true أو false' },
  { value: 'features.audio', kind: 'bool', hint: 'true أو false' },
  { value: 'features.announcements', kind: 'bool', hint: 'true أو false' },
  { value: 'audio.reciters', kind: 'list', hint: 'قائمة JSON' },
] as const;

/** `/config` (02 §6): remote config rows, typed per key, owner only. */
export function ConfigPage({ role }: { role: 'owner' | 'editor' }) {
  const queryClient = useQueryClient();
  const [error, setError] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['config'],
    queryFn: () => api.getJson<{ config: ConfigRow[] }>('/config'),
  });

  const create = useMutation({
    mutationFn: (values: Record<string, unknown>) => api.sendJson('POST', '/config', values),
    onSuccess: async () => {
      setError(null);
      await queryClient.invalidateQueries({ queryKey: ['config'] });
    },
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل الحفظ.'),
  });

  const remove = useMutation({
    mutationFn: (row: ConfigRow) =>
      api.sendJson('DELETE', '/config', {
        key: row.key,
        channel: row.channel,
        platform: row.platform,
      }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['config'] }),
  });

  if (role !== 'owner') {
    return <Alert type="warning" message="هذه الصفحة للمالك فقط." />;
  }

  return (
    <>
      <Typography.Title level={4}>الإعدادات البعيدة</Typography.Title>
      {error && <Alert type="error" message={error} style={{ marginBottom: 16 }} closable />}

      <Form
        layout="inline"
        style={{ marginBottom: 24, gap: 8, flexWrap: 'wrap' }}
        onFinish={(values: Record<string, unknown>) =>
          create.mutate({
            ...values,
            value: parseValue(String(values.key), String(values.raw)),
          })
        }
      >
        <Form.Item name="key" rules={[{ required: true }]}>
          <Select style={{ width: 260 }} placeholder="المفتاح" options={keys.map(({ value }) => ({ value }))} />
        </Form.Item>
        <Form.Item name="channel" initialValue="stable" rules={[{ required: true }]}>
          <Select
            style={{ width: 130 }}
            options={['stable', 'beta', 'internal'].map((value) => ({ value }))}
          />
        </Form.Item>
        <Form.Item name="raw" rules={[{ required: true }]}>
          <Input placeholder="القيمة" dir="ltr" style={{ width: 200 }} />
        </Form.Item>
        <Button type="primary" htmlType="submit" loading={create.isPending}>
          إضافة
        </Button>
      </Form>

      <Table
        rowKey={(row) => `${row.key}:${row.channel}:${row.platform}:${row.minBuild}:${row.maxBuild}`}
        loading={isLoading}
        dataSource={data?.config ?? []}
        pagination={false}
        columns={[
          { title: 'المفتاح', dataIndex: 'key', render: (value: string) => <code dir="ltr">{value}</code> },
          { title: 'القناة', dataIndex: 'channel' },
          { title: 'المنصة', dataIndex: 'platform', render: (value: string | null) => value ?? 'الكل' },
          {
            title: 'نطاق البناء',
            key: 'range',
            render: (_: unknown, row: ConfigRow) =>
              row.minBuild === null && row.maxBuild === null
                ? 'الكل'
                : `${row.minBuild ?? '—'} – ${row.maxBuild ?? '—'}`,
          },
          {
            title: 'القيمة',
            dataIndex: 'value',
            render: (value: unknown) => <code dir="ltr">{JSON.stringify(value)}</code>,
          },
          {
            title: '',
            key: 'delete',
            render: (_: unknown, row: ConfigRow) => (
              <Button size="small" danger onClick={() => remove.mutate(row)}>
                حذف
              </Button>
            ),
          },
        ]}
      />
    </>
  );
}

/** Turns the typed text into the JSON value the key expects (01 §4). */
function parseValue(key: string, raw: string): unknown {
  switch (key) {
    case 'updates.checkIntervalHours':
      return Number(raw);
    case 'updates.wifiOnlyDefault':
    case 'features.audio':
    case 'features.announcements':
      return raw === 'true';
    case 'audio.reciters':
      try {
        return JSON.parse(raw);
      } catch {
        return raw;
      }
    default:
      return raw;
  }
}
