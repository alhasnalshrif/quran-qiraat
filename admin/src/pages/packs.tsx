import { useState } from 'react';

import { Alert, Button, Form, Input, Modal, Table, Tag, Typography } from 'antd';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';

import * as api from '../api/client.js';

interface PackSummary {
  packId: string;
  titleAr: string;
  formatFamily: string;
  channels: Record<string, number>;
}

/** `/packs` (02 §6): the pack list, plus creating a new pack for owners. */
export function PacksPage({ role }: { role: 'owner' | 'editor' }) {
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['packs'],
    queryFn: () => api.getJson<{ packs: PackSummary[] }>('/packs'),
  });

  const create = useMutation({
    mutationFn: (values: { packId: string; titleAr: string; formatFamily: string }) =>
      api.sendJson('POST', '/packs', values),
    onSuccess: async () => {
      setCreating(false);
      setError(null);
      await queryClient.invalidateQueries({ queryKey: ['packs'] });
    },
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل الإنشاء.'),
  });

  return (
    <>
      <Typography.Title level={4}>الحزم</Typography.Title>

      {role === 'owner' && (
        <Button type="primary" onClick={() => setCreating(true)} style={{ marginBottom: 16 }}>
          حزمة جديدة
        </Button>
      )}

      <Table
        rowKey="packId"
        loading={isLoading}
        dataSource={data?.packs ?? []}
        pagination={false}
        columns={[
          {
            title: 'الحزمة',
            dataIndex: 'titleAr',
            render: (title: string, row: PackSummary) => <Link to={`/packs/${row.packId}`}>{title}</Link>,
          },
          { title: 'المعرّف', dataIndex: 'packId', render: (value: string) => <code dir="ltr">{value}</code> },
          { title: 'الصيغة', dataIndex: 'formatFamily', render: (value: string) => <span dir="ltr">{value}</span> },
          {
            title: 'القنوات',
            dataIndex: 'channels',
            render: (channels: Record<string, number>) =>
              Object.keys(channels).length === 0
                ? '—'
                : Object.entries(channels).map(([channel, version]) => (
                    <Tag
                      key={channel}
                      {...(channel === 'stable'
                        ? { color: 'green' }
                        : channel === 'beta'
                          ? { color: 'blue' }
                          : {})}
                    >
                      {channel} {version}
                    </Tag>
                  )),
          },
        ]}
      />

      <Modal
        open={creating}
        title="حزمة جديدة"
        onCancel={() => setCreating(false)}
        okText="إنشاء"
        cancelText="إلغاء"
        confirmLoading={create.isPending}
        onOk={() => {
          const form = document.getElementById('create-pack-form') as HTMLFormElement | null;
          form?.requestSubmit();
        }}
      >
        {error && <Alert type="error" message={error} style={{ marginBottom: 12 }} />}
        <Form
          id="create-pack-form"
          layout="vertical"
          onFinish={(values) => create.mutate(values as { packId: string; titleAr: string; formatFamily: string })}
        >
          <Form.Item name="packId" label="المعرّف" rules={[{ required: true }]} extra="من قائمة العقد فقط">
            <Input dir="ltr" placeholder="qiraat-farsh" />
          </Form.Item>
          <Form.Item name="titleAr" label="الاسم العربي" rules={[{ required: true }]}>
            <Input />
          </Form.Item>
          <Form.Item name="formatFamily" label="عائلة الصيغة" rules={[{ required: true }]}>
            <Input dir="ltr" placeholder="qiraat-variants" />
          </Form.Item>
        </Form>
      </Modal>
    </>
  );
}
