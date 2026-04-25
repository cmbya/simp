import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';

class SoopAccountService extends GetxService {
  static SoopAccountService get instance => Get.find<SoopAccountService>();

  var cookie = "";
  var hasCookie = false.obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kSoopCookie, "");
    hasCookie.value = cookie.isNotEmpty;
    setSite();
    super.onInit();
  }

  void setSite() {
    SoopSite.globalCookie = cookie;
    var site = (Sites.allSites["soop"]!.liveSite as SoopSite);
    site.cookie = cookie;
  }

  void setCookie(String cookie) {
    this.cookie = cookie;
    LocalStorageService.instance.setValue(
      LocalStorageService.kSoopCookie,
      cookie,
    );
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  void clearCookie() {
    cookie = "";
    LocalStorageService.instance.setValue(LocalStorageService.kSoopCookie, "");
    hasCookie.value = false;
    setSite();
  }
}
