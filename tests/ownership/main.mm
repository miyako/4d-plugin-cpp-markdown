#include "4DPluginAPI.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include "C_TEXT.h"
#include "ARRAY_TEXT.h"
#include "C_BLOB.h"
#include "4DPlugin-JSON.h"
#include <map>
#include <set>
#include <stdexcept>
#include <type_traits>
#include <cstring>
#include <iostream>

// Deny path boundaries even if a future fixture accidentally calls a path helper.
extern "C" CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef, CFStringRef,
                                                CFURLPathStyle, Boolean) {
    throw std::runtime_error("path operations prohibited");
}
extern "C" CFStringRef CFURLCopyFileSystemPath(CFURLRef, CFURLPathStyle) {
    throw std::runtime_error("path operations prohibited");
}
extern "C" void CGContextScaleCTM(CGContextRef, CGFloat, CGFloat) {
    throw std::runtime_error("drawing operations prohibited");
}
extern "C" void CGContextTranslateCTM(CGContextRef, CGFloat, CGFloat) {
    throw std::runtime_error("drawing operations prohibited");
}

namespace {
using Text = std::basic_string<PA_Unichar>;
std::map<PA_Unichar*, Text> strings;
std::map<PA_Handle, size_t> handles;
std::set<PA_Picture> pictures;
std::map<void*, int> refs;
PA_Variable property;
int failureCommand = 0;
bool failProperty = false;
int invalidResultInspections = 0;
int commandMode = 0;
int failures = 0, checks = 0;

void check(bool ok, const char* name) {
    ++checks;
    if (!ok) { ++failures; std::cerr << "FAIL " << name << "\n"; }
    else std::cout << "PASS " << name << "\n";
}
void require(bool ok) {
    if (!ok) throw std::runtime_error("invalid ownership or unexpected engine call");
}
PA_Unistring make(const PA_Unichar* p) {
    Text text(p ? p : reinterpret_cast<const PA_Unichar*>(u""));
    PA_Unistring s = {};
    s.fLength = static_cast<PA_long32>(text.size());
    s.fString = new PA_Unichar[text.size() + 1];
    std::copy(text.begin(), text.end(), s.fString);
    s.fString[text.size()] = 0;
    strings.emplace(s.fString, text);
    return s;
}
void dispose(PA_Unistring s) {
    if (s.fString) {
        require(strings.erase(s.fString) == 1);
        delete[] s.fString;
    }
}
void clear(PA_Variable& v) {
    switch (v.fType) {
        case eVK_Unistring: dispose(v.uValue.fString); break;
        case eVK_Picture:
            if (v.uValue.fPicture) {
                require(pictures.erase(v.uValue.fPicture) == 1);
                delete static_cast<int*>(v.uValue.fPicture);
            }
            break;
        case eVK_Object: case eVK_Collection: {
            void* p = v.fType == eVK_Object ? v.uValue.fObject : v.uValue.fCollection;
            if (p) {
                require(refs.count(p) && refs[p] > 0);
                if (--refs[p] == 0) { refs.erase(p); delete static_cast<int*>(p); }
            }
            break;
        }
        case eVK_ArrayUnicode:
            if (v.uValue.fArray.fData) {
                auto p = reinterpret_cast<PA_Unistring*>(*v.uValue.fArray.fData);
                for (int i = 0; i <= v.uValue.fArray.fNbElements; ++i) dispose(p[i]);
                free(*v.uValue.fArray.fData);
                handles.erase(v.uValue.fArray.fData);
                delete v.uValue.fArray.fData;
            }
            break;
        default: break;
    }
    v = {};
    v.fType = eVK_Undefined;
}
PA_Variable copy(PA_Variable v) {
    if (v.fType == eVK_Unistring) v.uValue.fString = make(v.uValue.fString.fString);
    if (v.fType == eVK_Object && v.uValue.fObject) ++refs.at(v.uValue.fObject);
    if (v.fType == eVK_Collection && v.uValue.fCollection) ++refs.at(v.uValue.fCollection);
    if (v.fType == eVK_Picture && v.uValue.fPicture) {
        v.uValue.fPicture = new int(0); pictures.insert(v.uValue.fPicture);
    }
    return v;
}
void engine(short selector, EngineBlock* eb) {
    eb->fError = eER_NoErr;
    switch (selector) {
        case EX_CREATE_UNISTRING:
            eb->fUniString1 = make(reinterpret_cast<PA_Unichar*>(eb->fHandle)); break;
        case EX_DISPOSE_UNISTRING: dispose(eb->fUniString1); break;
        case EX_SET_UNISTRING: {
            auto s = make(reinterpret_cast<PA_Unichar*>(eb->fHandle));
            dispose(eb->fUniString1); eb->fUniString1 = s; break;
        }
        case EX_CLEAR_VARIABLE: {
            auto v = static_cast<PA_Variable*>(eb->fPtr1);
            if ((failProperty || failureCommand) && v->fType == 0)
                ++invalidResultInspections;
            clear(*v); break;
        }
        case EX_VARIABLE_TO_STRING: {
            if (failProperty || failureCommand) {
                ++invalidResultInspections;
                eb->fUniString1 = {};
                break;
            }
            auto v = reinterpret_cast<PA_Variable*>(eb->fHandle);
            require(v->fType == eVK_Unistring);
            require(strings.count(v->uValue.fString.fString));
            eb->fUniString1 = v->uValue.fString; break;
        }
        case EX_HANDLE_MANAGER: {
            auto h = eb->fHandle;
            switch (eb->fParam1) {
                case 1:
                    h = new char*;
                    *h = static_cast<char*>(calloc(1, std::max<sLONG_PTR>(1, eb->fParam2)));
                    handles[h] = eb->fParam2; eb->fHandle = h; break;
                case 2:
                    require(handles.erase(h) == 1); free(*h); delete h; break;
                case 3: {
                    size_t old = handles.at(h);
                    *h = static_cast<char*>(realloc(*h, std::max<sLONG_PTR>(1, eb->fParam2)));
                    if (static_cast<size_t>(eb->fParam2) > old)
                        memset(*h + old, 0, eb->fParam2 - old);
                    handles[h] = eb->fParam2; break;
                }
                case 4: eb->fParam2 = handles.at(h); break;
                case 5: eb->fParam3 = reinterpret_cast<sLONG_PTR>(*h); break;
                case 6: break;
                default: throw std::runtime_error("unexpected handle operation");
            }
            break;
        }
        case EX_CREATE_PICTURE:
            eb->fPicture = new int(0); pictures.insert(eb->fPicture); break;
        case EX_DISPOSE_PICTURE:
            require(pictures.erase(eb->fPicture) == 1);
            delete static_cast<int*>(eb->fPicture); break;
        case EX_GET_OBJ_VALUE:
            if (failProperty) {
                // One permissible unspecified output: raw type zero normalizes
                // as text, so checking the kind is not a failure guard.
                memset(eb->fPtr2, 0, sizeof(PA_Variable));
                eb->fError = -1;
            } else *static_cast<PA_Variable*>(eb->fPtr2) = copy(property);
            break;
        case EX_SET_OBJ_VALUE: {
            clear(property);
            property = copy(*static_cast<PA_Variable*>(eb->fPtr2)); break;
        }
        case EX_EXECUTE_COMMAND_BY_ID: {
            auto result = static_cast<PA_Variable*>(eb->fPtr2);
            if (failureCommand == eb->fParam1) {
                memset(result, 0, sizeof(*result));
                eb->fError = -1; break;
            }
            switch (eb->fParam1) {
                case 1231: PA_SetBooleanVariable(result, 1); break;
                case 1225: {
                    void* p = new int(0); refs[p] = 1;
                    PA_SetObjectVariable(result, p); break;
                }
                case 1217:
                    if (commandMode == 1) *result = copy(property);
                    else { auto s = make(reinterpret_cast<const PA_Unichar*>(u"{\"ok\":true}"));
                           PA_SetStringVariable(result, &s); }
                    break;
                default: throw std::runtime_error("unexpected command ID");
            }
            break;
        }
        default: throw std::runtime_error("unexpected selector");
    }
}
void reset() {
    clear(property);
    // Keep failed cases independent, while accounting for every leaked owner.
    for (auto& s : strings) delete[] s.first;
    strings.clear();
    for (auto p : pictures) delete static_cast<int*>(p);
    pictures.clear();
    for (auto p : refs) delete static_cast<int*>(p.first);
    refs.clear();
    require(handles.empty());
}
void balance(const char* name) {
    clear(property);
    if (!strings.empty() || !pictures.empty() || !refs.empty() || !handles.empty())
        std::cerr << "live strings=" << strings.size() << " pictures=" << pictures.size()
                  << " reference owners=" << refs.size() << " handles=" << handles.size() << "\n";
    check(strings.empty() && pictures.empty() && refs.empty() && handles.empty(), name);
    reset();
}
}

int main() {
    gCall4D = engine;
    property.fType = eVK_Undefined;
    check(!std::is_copy_constructible<C_TEXT>::value, "C_TEXT noncopyable control");
    check(!std::is_copy_constructible<ARRAY_TEXT>::value &&
          !std::is_copy_assignable<ARRAY_TEXT>::value, "ARRAY_TEXT rejects shallow owner copies");
    check(!std::is_copy_constructible<C_BLOB>::value &&
          !std::is_copy_assignable<C_BLOB>::value, "C_BLOB rejects shallow owner copies");
    PA_ObjectRef obj = reinterpret_cast<void*>(1); // engine never dereferences host identities
    const char* values[] = {"", "ASCII", "\xc3\xa9", "\xf0\x9f\x98\x80"};
    for (const char* text : values) {
        ob_set_s(obj, "key", text);
        balance("narrow setter isolated owner balance");
        ob_set_s(obj, "key", text);
        CUTF8String got;
        check(ob_get_a(obj, L"key", &got) &&
              std::string(reinterpret_cast<const char*>(got.c_str()), got.size()) == text,
              "narrow setter/getter content");
        balance("narrow setter/getter owner balance");
        ob_set_s(obj, L"key", text);
        balance("wide-key setter owner balance");
    }
    ob_set_a(obj, L"key", L"wide \u00e9 \U0001f600");
    balance("wide-value setter owner balance");
    CUTF16String native(reinterpret_cast<const PA_Unichar*>(u"native \u00e9 \U0001f600"));
    ob_set_a(obj, L"key", &native);
    balance("native UTF16 setter owner balance");
    ob_set_p(obj, L"key", PA_CreatePicture(nullptr, 0));
    balance("picture setter owner balance");
    for (bool narrow : {false, true}) {
        void* p = new int(0); refs[p] = 1;
        if (narrow) ob_set_o(obj, "key", p);
        else ob_set_o(obj, L"key", p);
        balance("object setter handoff owners");
    }
    ob_set_b(obj, L"key", true);
    check(ob_get_b(obj, L"key"), "boolean getter content control");
    balance("boolean property owners");
    ob_set_n(obj, L"key", 3.5);
    check(ob_get_n(obj, L"key") == 3.5, "real getter content control");
    balance("real property owners");
    ob_set_n(obj, "key", 7.5);
    check(ob_get_n(obj, L"key") == 7.5, "narrow real setter content control");
    balance("narrow real property owners");
    ob_set_i(obj, L"key", 42);
    check(PA_GetLongintVariable(property) == 42, "integer property content control");
    balance("integer property owners");
    ob_set_0(obj, L"key");
    check(property.fType == static_cast<char>(eVK_Null), "wide null property content control");
    balance("wide null property owners");
    ob_set_0(obj, "key");
    check(property.fType == static_cast<char>(eVK_Null) && ob_is_defined(obj, L"key"),
          "narrow null and existence content control");
    balance("narrow null property owners");
    for (int kind : {eVK_Unistring, eVK_Object, eVK_Collection}) {
        if (kind == eVK_Unistring) {
            auto s = make(reinterpret_cast<const PA_Unichar*>(u"mismatch"));
            PA_SetStringVariable(&property, &s);
        } else {
            void* p = new int(0); refs[p] = 1;
            if (kind == eVK_Object) PA_SetObjectVariable(&property, p);
            else PA_SetCollectionVariable(&property, p);
        }
        CUTF8String ignored;
        ob_get_a(obj, L"key", &ignored);
        ob_get_b(obj, L"key");
        ob_get_n(obj, L"key");
        auto collection = ob_get_c(obj, L"key");
        if (collection) PA_DisposeCollection(collection);
        balance("all getter success/mismatch owner balance");
    }
    void* collection = new int(0); refs[collection] = 1;
    ob_set_c(obj, L"key", collection);
    auto returned = ob_get_c(obj, L"key");
    clear(property);
    check(refs.count(returned) && refs[returned] == 1, "collection result independent owner");
    PA_DisposeCollection(returned);
    balance("collection handoff balance");
    for (int mode : {0, 1}) {
        commandMode = mode;
        if (mode) {
            auto s = make(reinterpret_cast<const PA_Unichar*>(u"string result"));
            PA_SetStringVariable(&property, &s);
        }
        CUTF8String result;
        ob_stringify(obj, &result);
        check(!result.empty(), "stringify success content");
        balance("stringify success owners");
    }
    commandMode = 1;
    PA_SetBooleanVariable(&property, 1);
    CUTF8String mismatch;
    ob_stringify(obj, &mismatch);
    check(mismatch.empty(), "stringify type mismatch control");
    balance("stringify mismatch owners");
    for (int kind : {eVK_Object, eVK_Collection}) {
        void* p = new int(0); refs[p] = 1;
        if (kind == eVK_Object) PA_SetObjectVariable(&property, p);
        else PA_SetCollectionVariable(&property, p);
        CUTF8String s;
        ob_stringify(obj, &s);
        check(s.empty(), "stringify owned type-mismatch content control");
        balance("stringify owned type-mismatch owners");
    }
    for (int id : {1225, 1217}) {
        failureCommand = id;
        invalidResultInspections = 0;
        bool threw = false;
        try { CUTF8String s; ob_stringify(obj, &s); }
        catch (const std::runtime_error& e) {
            threw = std::string(e.what()).find("-1") != std::string::npos;
        }
        check(threw && invalidResultInspections == 0,
              "failed command reported before result adoption");
        failureCommand = 0;
        balance("failed command owners");
    }
    failureCommand = 1231;
    for (int getter = 0; getter < 5; ++getter) {
        bool threw = false;
        try {
            CUTF8String s;
            switch (getter) {
                case 0: ob_get_a(obj, L"key", &s); break;
                case 1: ob_get_b(obj, L"key"); break;
                case 2: ob_get_n(obj, L"key"); break;
                case 3: ob_get_c(obj, L"key"); break;
                case 4: ob_is_defined(obj, L"key"); break;
            }
        } catch (const std::runtime_error& e) {
            threw = std::string(e.what()).find("-1") != std::string::npos;
        }
        check(threw, "failed property-existence command reported");
        balance("failed property-existence owners");
    }
    failureCommand = 0;
    for (int getter = 0; getter < 4; ++getter) {
        failProperty = true;
        invalidResultInspections = 0;
        bool threw = false;
        try {
            CUTF8String s;
            switch (getter) {
                case 0: ob_get_a(obj, L"key", &s); break;
                case 1: ob_get_b(obj, L"key"); break;
                case 2: ob_get_n(obj, L"key"); break;
                case 3: ob_get_c(obj, L"key"); break;
            }
        } catch (const std::runtime_error& e) {
            threw = std::string(e.what()).find("-1") != std::string::npos;
        }
        check(threw && invalidResultInspections == 0,
              "failed property reported before result adoption");
        failProperty = false;
        balance("failed property owners");
    }

    // Actual array wrapper, including reserved index zero, reuse and borrowed reads.
    for (int n : {0, 1, 8, 64}) {
        PA_Variable array = PA_CreateVariable(eVK_ArrayUnicode);
        uint8_t* args[] = {reinterpret_cast<uint8_t*>(&array)};
        ARRAY_TEXT text;
        text.setSize(n + 1);
        for (int i = 0; i <= n; ++i) text.setUTF16StringAtIndex(&native, i);
        text.toParamAtIndex(args, 1);
        text.toParamAtIndex(args, 1);
        for (int i = 0; i < 128; ++i) {
            auto churn = make(reinterpret_cast<const PA_Unichar*>(u"allocator churn"));
            dispose(churn);
        }
        PA_Variable second = PA_CreateVariable(eVK_ArrayUnicode);
        uint8_t* secondArgs[] = {reinterpret_cast<uint8_t*>(&second)};
        text.toParamAtIndex(secondArgs, 1);
        auto firstValue = PA_GetStringInArray(array, 0);
        auto secondValue = PA_GetStringInArray(second, 0);
        check(firstValue.fString != secondValue.fString, "array outputs independent owners");
        PA_SetStringInArray(array, 0, nullptr);
        check(PA_GetStringInArray(array, 0).fString == firstValue.fString,
              "null array input preserves old owner");
        ARRAY_TEXT snapshot; snapshot.fromParamAtIndex(args, 1);
        CUTF16String got; snapshot.copyUTF16StringAtIndex(&got, n);
        check(got == native && snapshot.getSize() == static_cast<unsigned>(n + 1),
              "array transfer reuse content and index zero");
        PA_ResizeArray(&array, 0);
        PA_ClearVariable(&array);
        PA_ClearVariable(&second);
        balance("array resize clear owners");
    }
    for (int rejected : {-1, 1, 2}) {
        PA_Variable array = PA_CreateVariable(eVK_ArrayUnicode);
        auto s = make(reinterpret_cast<const PA_Unichar*>(u"caller retained"));
        PA_Variable dest = array;
        int index = rejected;
        if (rejected == 2) { dest.fType = eVK_Boolean; index = 0; }
        PA_SetStringInArray(dest, index, &s);
        check(strings.count(s.fString) == 1, "rejected array assignment retains caller owner");
        PA_DisposeUnistring(&s); PA_ClearVariable(&array);
        balance("rejected assignment owner control");
    }
    {
        PA_Variable dest = {};
        dest.fType = eVK_ArrayUnicode;
        auto s = make(reinterpret_cast<const PA_Unichar*>(u"caller retained"));
        PA_SetStringInArray(dest, 0, &s);
        check(strings.count(s.fString) == 1, "null array data retains owner");
        PA_DisposeUnistring(&s);
        balance("null array data owner control");
    }
    for (const char* text : values) {
        for (size_t size : {size_t(0), size_t(1), size_t(15), size_t(16), size_t(127)}) {
            std::string bytes;
            for (size_t i = 0; i < size; ++i) bytes += text;
            C_TEXT scalar;
            for (int repeat = 0; repeat < 3; ++repeat) {
                scalar.setUTF8String(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
                CUTF8String roundtrip;
                scalar.copyUTF8String(&roundtrip);
                check(std::string(reinterpret_cast<const char*>(roundtrip.data()),
                                  roundtrip.size()) == bytes &&
                      scalar.getUTF16StringPtr()[scalar.getUTF16Length()] == 0,
                      "C_TEXT UTF8/UTF16 units capacity termination reuse control");
            }
        }
    }
    // Public exported dispatcher and real parser; only in-memory fixtures.
    for (const char* text : {"", "# Heading", "plain", "\xc3\xa9", "\xf0\x9f\x98\x80"}) {
        C_TEXT input;
        input.setUTF8String(reinterpret_cast<const uint8_t*>(text), strlen(text));
        PA_Unistring in = make(input.getUTF16StringPtr());
        PA_Unistring out = make(reinterpret_cast<const PA_Unichar*>(u"stale"));
        PA_Unistring* result = &out;
        uint8_t* args[] = {reinterpret_cast<uint8_t*>(&in)};
        PluginBlock params = {};
        params.fParameters = args; params.fResult = &result;
        PluginMain(1, &params);
        require(strings.count(out.fString));
        Text expected;
        if (*text) {
            C_TEXT html;
            std::string bytes = std::string(text) == "# Heading" ? "<h1>Heading</h1>\n" :
                                "<p>" + std::string(text) + "</p>\n\n";
            html.setUTF8String(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
            expected.assign(html.getUTF16StringPtr(), html.getUTF16Length());
        }
        if (strings.at(out.fString) != expected) {
            std::cerr << "dispatcher input=" << text << " actual units:";
            for (auto unit : strings.at(out.fString)) std::cerr << " " << unsigned(unit);
            std::cerr << "\n";
        }
        check(strings.at(out.fString) == expected &&
              out.fString[out.fLength] == 0, "exported dispatcher exact UTF16 output");
        dispose(in); dispose(out);
        balance("exported dispatcher owner control");
    }
    {
        std::string oversized(1024 * 1024 + 1, 'a');
        C_TEXT input;
        input.setUTF8String(reinterpret_cast<const uint8_t*>(oversized.data()), oversized.size());
        PA_Unistring in = make(input.getUTF16StringPtr());
        PA_Unistring out = make(reinterpret_cast<const PA_Unichar*>(u"stale"));
        PA_Unistring* result = &out;
        uint8_t* args[] = {reinterpret_cast<uint8_t*>(&in)};
        PluginBlock params = {};
        params.fParameters = args; params.fResult = &result;
        PluginMain(1, &params);
        check(out.fLength == 0, "exported dispatcher oversize guard control");
        dispose(in); dispose(out);
        balance("exported dispatcher oversize owners");
    }
    std::cout << "checks=" << checks << " failures=" << failures << "\n";
    return failures ? 1 : 0;
}
