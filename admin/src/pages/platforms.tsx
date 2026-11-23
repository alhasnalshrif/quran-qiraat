import { Alert, Button, Card, Form, Input, InputNumber, Tabs, Typography } from 'antd';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';

import * as api from '../api/client.js';

interface PlatformRow {
  platform: 'ios' | 'android';
  latestBuild: number;
  minSupportedBuild: number;
  storeUrl: string | null;
  messageAr: string | null;
}

/** `/platforms` (02 §6): the latest and minimum build per platform. */
export function PlatformsPage({ role }: { role: 'owner' | 'editor' }) {
  return (
    <>
      <Typography.Title level={4}>النسخ والمنصات</Typography.Title>
      <Tabs
        items={[
          { key: 'ios', label: 'iOS', children: <PlatformForm platform="ios" role={role} /> },
          { key: 'android', label: 'Android', children: <PlatformForm platform="android" role={role} /> },
        ]}
      />
    </>
  );
}

function PlatformForm({ platform, role }: { platform: 'ios' | 'android'; role: 'owner' | 'editor' }) {
  const queryClient = useQueryClient();
  const [saved, setSaved] = useState(false);

  const { data } = useQuery({
    queryKey: ['platform', platform],
    queryFn: () => api.getJson<{ platform: PlatformRow | null }>(`/platforms/${platform}`),
  });

  const save = useMutation({
    mutationFn: (values: Omit<PlatformRow, 'platform'>) =>
      api.sendJson('PUT', `/platforms/${platform}`, values),
    onSuccess: async () => {
      setSaved(true);
      await queryClient.invalidateQueries({ queryKey: ['platform', platform] });
    },
  });

  const current = data?.platform ?? null;

  return (
    <Card>
      {saved && <Alert type="success" message="حُفظت القيم." style={{ marginBottom: 16 }} closable />}
      {save.error && (
        <Alert
          type="error"
          message={save.error instanceof Error ? save.error.message : 'فشل الحفظ.'}
          style={{ marginBottom: 16 }}
        />
      )}

      <Form
        layout="vertical"
        disabled={role !== 'owner'}
        key={current ? 'loaded' : 'empty'}
        initialValues={
          current ?? { latestBuild: 1, minSupportedBuild: 1, storeUrl: '', messageAr: '' }
        }
        onFinish={(values) => save.mutate(values as Omit<PlatformRow, 'platform'>)}
      >
        <Form.Item name="latestBuild" label="أحدث بناء" rules={[{ required: true }]}>
          <InputNumber min={1} style={{ width: 160 }} />
        </Form.Item>
        <Form.Item
          name="minSupportedBuild"
          label="أقل بناء مدعوم"
          rules={[{ required: true }]}
          extra="من هو أدنى من هذا يرى شاشة التحديث الإجباري"
        >
          <InputNumber min={1} style={{ width: 160 }} />
        </Form.Item>
        <Form.Item name="storeUrl" label="رابط المتجر">
          <Input dir="ltr" />
        </Form.Item>
        <Form.Item name="messageAr" label="رسالة التحديث (عربي)">
          <Input.TextArea rows={2} />
        </Form.Item>
        {role === 'owner' && (
          <Button type="primary" htmlType="submit" loading={save.isPending}>
            حفظ
          </Button>
        )}
      </Form>
    </Card>
  );
}
