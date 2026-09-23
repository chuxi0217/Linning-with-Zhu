import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const FORM_IDS_KEY: string = 'zanjia_form_ids';

// 咱家桌面卡片：姐姐状态灯 + 第几天 + 姐姐最新一句话
// 数据流：app 写 preferences 并主动 updateForm；系统定时刷新走 onUpdateForm 读 preferences
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.['ohos.extra.param.key.form_identity'] as string;
    if (formId) {
      const prefs = preferences.getPreferencesSync(this.context, { name: 'zanjia' });
      const raw = prefs.getSync(FORM_IDS_KEY, '[]') as string;
      const ids = JSON.parse(raw) as string[];
      if (!ids.includes(formId)) {
        ids.push(formId);
        prefs.putSync(FORM_IDS_KEY, JSON.stringify(ids));
        prefs.flushSync();
      }
    }
    return this.readCardData();
  }

  onUpdateForm(formId: string): void {
    formProvider.updateForm(formId, this.readCardData());
  }

  onRemoveForm(formId: string): void {
    const prefs = preferences.getPreferencesSync(this.context, { name: 'zanjia' });
    const raw = prefs.getSync(FORM_IDS_KEY, '[]') as string;
    const ids = (JSON.parse(raw) as string[]).filter((id: string) => id !== formId);
    prefs.putSync(FORM_IDS_KEY, JSON.stringify(ids));
    prefs.flushSync();
  }

  private readCardData(): formBindingData.FormBindingData {
    const prefs = preferences.getPreferencesSync(this.context, { name: 'zanjia' });
    const obj: Record<string, string> = {
      'statusLamp': prefs.getSync('statusLamp', '● 醒着') as string,
      'dayNo': prefs.getSync('dayNo', '—') as string,
      'lastReply': prefs.getSync('lastReply', '姐姐在这儿') as string,
    };
    return formBindingData.createFormBindingData(obj);
  }
}
